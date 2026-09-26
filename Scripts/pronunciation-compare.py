#!/usr/bin/env python3
"""Compare chat models on pronunciation scoring with the app's own prompt.

Usage: Scripts/pronunciation-compare.py 9r-gemini-low 9r-gemini-lite [...]

Cases live in Scripts/pronunciation-cases.json. A case with "spoken" is synthesized with `say`
(so "I sink ..." gives audio that really contains the error); a case with "file" uses your own
recording. "expect" lists the target words the model should flag; [] means a clean read.
API key: $NTRANSLATE_API_KEY, else the app's Keychain item.
"""
import base64, json, os, pathlib, re, subprocess, sys, tempfile, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = pathlib.Path.home() / "Library/Application Support/NTranslate/config.json"


def app_prompt():
    # Read the prompt from source so this script never drifts from what the app sends.
    src = (ROOT / "Sources/translate/AskDictation.swift").read_text()
    body = re.search(r'static let pronunciationPrompt = """\n(.*?)\n\s*"""', src, re.S).group(1)
    return "\n".join(line[4:] if line.startswith("    ") else line for line in body.splitlines())


def api_key():
    return os.environ.get("NTRANSLATE_API_KEY") or subprocess.check_output(
        ["security", "find-generic-password", "-s", "local.ninh.ntranslate", "-a", "apiKey", "-w"], text=True).strip()


def audio_for(case, tmp):
    if "file" in case:
        return pathlib.Path(case["file"]).expanduser()
    out = pathlib.Path(tmp) / (re.sub(r"\W+", "-", case["spoken"])[:40] + ".wav")
    subprocess.run(["say", "-v", case.get("voice", "Samantha"), "-o", str(out),
                    "--data-format=LEI16@16000", case["spoken"]], check=True)
    return out


def assess(url, key, model, prompt, target, wav):
    payload = {
        "model": model, "stream": False, "temperature": 0, "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": [
                {"type": "text", "text": f"<target_sentence>\n{target}\n</target_sentence>"},
                {"type": "input_audio", "input_audio": {"data": base64.b64encode(wav.read_bytes()).decode(), "format": "wav"}},
            ]},
        ],
    }
    req = urllib.request.Request(url, json.dumps(payload).encode(),
                                 {"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    content = json.load(urllib.request.urlopen(req, timeout=120))["choices"][0]["message"]["content"]
    return json.loads(content[content.index("{"):content.rindex("}") + 1])


def main():
    models = sys.argv[1:] or ["9r-gemini-low", "9r-gemini-lite"]
    cases = json.loads((ROOT / "Scripts/pronunciation-cases.json").read_text())
    url, key, prompt = json.loads(CONFIG.read_text())["apiBaseURL"], api_key(), app_prompt()
    totals = {m: {"hit": 0, "miss": 0, "false": 0, "fail": 0} for m in models}
    with tempfile.TemporaryDirectory() as tmp:
        for case in cases:
            wav = audio_for(case, tmp)
            expect = {w.lower() for w in case["expect"]}
            print(f"\n{case['target']}  (audio: {case.get('spoken', case.get('file'))}, expect: {sorted(expect) or 'clean'})")
            for m in models:
                try:
                    r = assess(url, key, m, prompt, case["target"], wav)
                except Exception as e:  # one bad call should not end the run
                    totals[m]["fail"] += 1
                    print(f"  {m:24} ERROR {e}")
                    continue
                got = {str(e.get("word", "")).lower() for e in r.get("errors", [])}
                hit, miss, false = expect & got, expect - got, got - expect
                t = totals[m]
                t["hit"] += len(hit); t["miss"] += len(miss); t["false"] += len(false)
                print(f"  {m:24} score {r.get('score')!s:>3}  heard: {r.get('heard')!r}"
                      f"  hit {sorted(hit)} miss {sorted(miss)} false {sorted(false)}")
    print("\nSummary (higher hit, lower miss/false is better)")
    for m, t in totals.items():
        print(f"  {m:24} hit {t['hit']}  miss {t['miss']}  false {t['false']}  failed calls {t['fail']}")


if __name__ == "__main__":
    main()
