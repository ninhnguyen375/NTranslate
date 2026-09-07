#!/usr/bin/env python3
"""Chấm chất lượng thẻ từ vựng (vocab pack + saved words) qua 9Router.

    ./Scripts/vocab-audit.py            # 50 từ chưa chấm
    ./Scripts/vocab-audit.py 20         # 20 từ
    ./Scripts/vocab-audit.py --report   # xem tổng kết, không gọi model
    ./Scripts/vocab-audit.py --fix 20   # sửa 20 thẻ điểm thấp (pack + saved)
    ./Scripts/vocab-audit.py --auto 50  # chấm 50 từ, sửa thẻ kém, chấm lại

Sửa saved word phải tắt NTranslate trước, vì app giữ record trong bộ nhớ.

Hết từ chưa chấm thì tự quay lại chấm những từ điểm thấp (< --threshold).
"""
import json, os, sys, glob, urllib.request, datetime, argparse, re, threading
from concurrent.futures import ThreadPoolExecutor

DATA = "/Volumes/ESSD/MacData/NTranslateData"
PACK = os.path.join(os.path.dirname(__file__), "..", "Resources", "vocab-en-vi.json")
STATE = os.path.join(DATA, "vocab-audit.json")
MODEL = "9r-gemini"
CHUNK = 10  # từ mỗi request
WORKERS = int(os.environ.get("VOCAB_AUDIT_WORKERS", "4"))  # request song song

PROMPT = """Bạn là biên tập viên từ điển Anh-Việt khó tính. Dưới đây là các thẻ học từ vựng.
Chấm mỗi thẻ 0-10 dựa trên: nghĩa tiếng Việt có đúng và đủ không, phiên âm IPA có chuẩn không,
nhãn CEFR/mức dùng có hợp lý không, ví dụ và bản dịch có tự nhiên và đúng ngữ pháp không,
phần "dễ nhầm với" và collocation có chính xác không.
10 = không lỗi. 7-9 = lỗi nhỏ. 4-6 = lỗi làm người học hiểu sai. 0-3 = sai nghiêm trọng.

Chấm ĐỦ mọi thẻ, đúng số id được đánh.
Chỉ trả JSON array, không giải thích thêm:
[{"id":1,"score":8,"issues":["lỗi cụ thể, ngắn gọn, tiếng Việt"]}]
issues để [] nếu thẻ sạch.

THẺ:
"""


FIX_PROMPT = """Bạn là biên tập viên từ điển Anh-Việt. Nhiệm vụ: sửa một thẻ học từ vựng đã có lỗi,
trả về thẻ hoàn chỉnh đã sửa.

Thẻ này được sinh ra theo bộ quy tắc dưới đây. Thẻ sau khi sửa phải thỏa MỌI quy tắc,
không riêng các lỗi được liệt kê:

<quy-tắc-thẻ>
{rules}
</quy-tắc-thẻ>

<lỗi-đã-phát-hiện>
{issues}
</lỗi-đã-phát-hiện>

<thẻ-gốc>
{card}
</thẻ-gốc>

Cách làm:
1. Sửa từng lỗi trong <lỗi-đã-phát-hiện>.
2. Rà lại toàn bộ thẻ theo <quy-tắc-thẻ> và sửa cả những lỗi chưa được liệt kê,
   đặc biệt: câu tiếng Anh thiếu mạo từ hoặc sở hữu cách, ví dụ không chứa đúng
   từ gốc, collocation viết thiếu mạo từ, phiên âm sai, từ nguyên bịa trong "Nhớ nhanh".
3. Giữ nguyên phần đã đúng: cùng bố cục, cùng thứ tự mục, cùng cách viết nhãn,
   cùng số lượng ví dụ. Không thêm mục mới, không bỏ mục đang có.

Chỉ trả về nội dung thẻ đã sửa, bắt đầu bằng "Từ gốc:". Không markdown, không giải thích.

Thẻ đã sửa:
"""

# Nguồn duy nhất của quy tắc thẻ là prompt trong app; đọc thẳng từ source để prompt
# sửa thẻ không lệch khi prompt sinh thẻ đổi.
PROMPTS_SWIFT = os.path.join(os.path.dirname(__file__), "..",
                             "Sources", "translate", "AppConfigPrompts.swift")


def card_rules():
    """Phần "Hard rules:" của defaultLearnPrompt, đã bỏ thụt lề Swift."""
    try:
        src = open(PROMPTS_SWIFT).read()
    except OSError:
        return "(không đọc được quy tắc thẻ)"
    m = re.search(r'static let defaultLearnPrompt = """\n(.*?)\n    """', src, re.S)
    if not m:
        return "(không đọc được quy tắc thẻ)"
    body = "\n".join(l[4:] if l.startswith("    ") else l for l in m.group(1).split("\n"))
    i = body.find("Hard rules:")
    rules = body[i:].strip() if i >= 0 else body.strip()
    return (rules.replace("{{config.sourceLang}}", "English")
                 .replace("{{config.targetLang}}", "Vietnamese"))


def saved_index():
    """word -> (đường dẫn file, id record) cho các thẻ saved."""
    idx = {}
    for f in glob.glob(os.path.join(DATA, "devices", "*", "*.json")):
        d = json.load(open(f))
        for r in (d.get("records", d) if isinstance(d, dict) else d):
            if not r.get("isSaved"):
                continue
            m = re.match(r"Từ gốc:\s*(.+)", r.get("resultText", ""))
            w = m.group(1).strip() if m else (r.get("sourceText") or "").strip()
            if w and len(w.split()) <= 4:
                idx[w] = (f, r["id"])
    return idx


def write_saved(path, record_id, text):
    d = json.load(open(path))
    recs = d.get("records", d) if isinstance(d, dict) else d
    for r in recs:
        if r["id"] == record_id:
            r["resultText"] = text
            r["updatedAt"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            break
    else:
        return False
    tmp = path + ".tmp"
    json.dump(d, open(tmp, "w"), ensure_ascii=False)
    os.replace(tmp, path)
    return True


def load_cards():
    cards = {}
    pack = json.load(open(PACK))
    for e in pack["entries"]:
        cards[e["w"]] = {"text": e["r"], "src": "pack"}
    for f in glob.glob(os.path.join(DATA, "devices", "*", "*.json")):
        d = json.load(open(f))
        for r in (d.get("records", d) if isinstance(d, dict) else d):
            if not r.get("isSaved"):
                continue
            m = re.match(r"Từ gốc:\s*(.+)", r.get("resultText", ""))
            w = m.group(1).strip() if m else (r.get("sourceText") or "").strip()
            if len(w.split()) > 4:
                continue  # đoạn văn đã lưu, không phải thẻ từ vựng
            if w:
                cards[w] = {"text": r.get("resultText", ""), "src": "saved"}
    return cards


def app_running():
    return os.system("pgrep -qf /Applications/NTranslate.app/Contents/MacOS/NTranslate") == 0


def load_state():
    if os.path.exists(STATE):
        return json.load(open(STATE))
    return {"version": 1, "audited": {}}


def save_state(s):
    tmp = STATE + ".tmp"
    json.dump(s, open(tmp, "w"), ensure_ascii=False, indent=1)
    os.replace(tmp, STATE)


def ask(cards_slice):
    body = PROMPT + "\n\n".join(f"### id {i}\n{c['text']}"
                                 for i, (w, c) in enumerate(cards_slice, 1))
    txt = chat(body)
    m = re.search(r"\[.*\]", txt, re.S)
    if not m:
        raise ValueError("model không trả JSON: " + txt[:200])
    return json.loads(m.group(0))


def app_running():
    return os.system("pgrep -qf /Applications/NTranslate.app/Contents/MacOS/NTranslate") == 0


def load_state():
    if os.path.exists(STATE):
        return json.load(open(STATE))
    return {"version": 1, "audited": {}}


def save_state(s):
    tmp = STATE + ".tmp"
    json.dump(s, open(tmp, "w"), ensure_ascii=False, indent=1)
    os.replace(tmp, STATE)


def ask(cards_slice):
    body = PROMPT + "\n\n".join(f"### id {i}\n{c['text']}"
                                 for i, (w, c) in enumerate(cards_slice, 1))
    req = urllib.request.Request(
        os.environ["NINEROUTER_URL"] + "/v1/chat/completions",
        data=json.dumps({"model": MODEL, "messages": [{"role": "user", "content": body}],
                         "stream": False}).encode(),
        headers={"Content-Type": "application/json",
                 "Authorization": "Bearer " + os.environ.get("NINEROUTER_KEY", "")},
    )
    txt = json.loads(urllib.request.urlopen(req, timeout=300).read())["choices"][0]["message"]["content"]
    m = re.search(r"\[.*\]", txt, re.S)
    if not m:
        raise ValueError("model không trả JSON: " + txt[:200])
    return json.loads(m.group(0))


def chat(body):
    req = urllib.request.Request(
        os.environ["NINEROUTER_URL"] + "/v1/chat/completions",
        data=json.dumps({"model": MODEL, "messages": [{"role": "user", "content": body}],
                         "stream": False}).encode(),
        headers={"Content-Type": "application/json",
                 "Authorization": "Bearer " + os.environ.get("NINEROUTER_KEY", "")},
    )
    return json.loads(urllib.request.urlopen(req, timeout=300).read())["choices"][0]["message"]["content"]


def fix(state, n, threshold, src="all", force=False):
    """Sửa thẻ điểm thấp: ghi lại vocab pack và/hoặc record saved trong devices/."""
    done = state["audited"]
    targets = [w for w, v in done.items()
               if v["score"] < threshold and v["issues"] and not v.get("skip")
               and (src == "all" or v["src"] == src)]
    targets.sort(key=lambda w: done[w]["score"])
    targets = targets[:n]
    if not targets:
        print("Không có thẻ nào cần sửa.")
        return []

    touches_saved = any(done[w]["src"] == "saved" for w in targets)
    if touches_saved and not force and app_running():
        print("NTranslate đang chạy: thoát app rồi chạy lại, hoặc thêm --force "
              "(app có thể ghi đè record từ bộ nhớ).", file=sys.stderr)
        return []

    pack = json.load(open(PACK))
    index = {e["w"]: e for e in pack["entries"]}
    saved = saved_index() if touches_saved else {}
    print(f"Sửa {len(targets)} thẻ bằng {MODEL}...")

    jobs = []
    for w in targets:
        origin = done[w]["src"]
        if origin == "pack":
            entry = index.get(w)
            old_text = entry["r"] if entry else None
        else:
            loc = saved.get(w)
            old_text = None
            if loc:
                d = json.load(open(loc[0]))
                recs = d.get("records", d) if isinstance(d, dict) else d
                old_text = next((r["resultText"] for r in recs if r["id"] == loc[1]), None)
        if not old_text:
            print(f"  {w}: không tìm thấy thẻ gốc, bỏ qua", file=sys.stderr)
            continue
        jobs.append((w, origin, old_text))

    rules = card_rules()

    def rewrite(job):
        w, origin, old_text = job
        try:
            new = chat(FIX_PROMPT.format(
                rules=rules,
                issues="\n".join("- " + i for i in done[w]["issues"]),
                card=old_text)).strip()
        except Exception as e:
            return w, origin, old_text, None, f"lỗi {e}"
        new = re.sub(r"^```[a-z]*\n|\n```$", "", new).strip()
        if not new.startswith("Từ gốc:") or len(new) < len(old_text) * 0.5:
            return w, origin, old_text, None, "model trả về định dạng lạ"
        return w, origin, old_text, new, None

    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        results = list(ex.map(rewrite, jobs))

    fixed_pack, fixed_saved = [], []
    for w, origin, old_text, new, err in results:
        if err:
            print(f"  {w}: {err}, bỏ qua", file=sys.stderr)
            continue
        if origin == "pack":
            index[w]["r"] = new
            fixed_pack.append(w)
        else:
            if not write_saved(saved[w][0], saved[w][1], new):
                print(f"  {w}: không ghi được record", file=sys.stderr)
                continue
            fixed_saved.append(w)
        print(f"  {w} đã sửa ({origin})")

    if fixed_pack:
        backup = PACK + ".bak"
        if not os.path.exists(backup):
            os.replace(PACK, backup)
        else:
            os.remove(PACK)
        with open(PACK, "w") as f:
            json.dump(pack, f, ensure_ascii=False, separators=(",", ":"))
        print(f"Ghi lại {PACK} (backup: {backup}).")
    for w in fixed_pack + fixed_saved:
        state["audited"].pop(w, None)   # để lần chấm sau kiểm tra lại
    if fixed_pack or fixed_saved:
        save_state(state)
        print(f"\nĐã sửa {len(fixed_pack)} thẻ pack, {len(fixed_saved)} saved word. "
              "Điểm cũ đã xoá, lần chấm tới sẽ kiểm tra lại.")
    return fixed_pack + fixed_saved


def pick(cards, state, n, threshold, src="all"):
    done = state["audited"]
    if src != "all":
        cards = {w: c for w, c in cards.items() if c["src"] == src}
    fresh = [w for w in cards if w not in done]
    if fresh:
        return sorted(fresh)[:n], "mới"
    low = [w for w in cards if done[w]["score"] < threshold and not done[w].get("skip")]
    low.sort(key=lambda w: (done[w]["score"], done[w]["at"]))
    return low[:n], "chấm lại điểm thấp"


def audit(cards, state, words, mode):
    print(f"Chấm {len(words)} từ ({mode}) bằng {MODEL}...")
    now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")

    lock = threading.Lock()

    def run(batch_words, chunk):
        """Chấm các nhóm song song, trả về danh sách từ model không chấm."""
        groups = [batch_words[i:i + chunk] for i in range(0, len(batch_words), chunk)]
        missing = []

        def do(idx_group):
            idx, group = idx_group
            try:
                results = ask([(w, cards[w]) for w in group])
            except Exception as e:
                with lock:
                    print(f"  lỗi batch {idx}: {e}", file=sys.stderr)
                return group
            scored = set()
            with lock:
                for r in results:
                    try:
                        w = group[int(r["id"]) - 1]
                    except (KeyError, ValueError, IndexError):
                        continue
                    prev = state["audited"].get(w, {})
                    state["audited"][w] = {
                        "score": int(r.get("score", 0)),
                        "issues": r.get("issues") or [],
                        "src": cards[w]["src"],
                        "at": now,
                        "round": prev.get("round", 0) + 1,
                        **({"skip": True} if prev.get("skip") else {}),
                    }
                    scored.add(w)
                save_state(state)
                print(f"  batch {idx}/{len(groups)} xong ({len(scored)}/{len(group)})")
            return [w for w in group if w not in scored]

        with ThreadPoolExecutor(max_workers=WORKERS) as ex:
            for left in ex.map(do, enumerate(groups, 1)):
                missing += left
        return missing

    missing = run(words, CHUNK)
    if missing:
        print(f"Chấm lại {len(missing)} từ model bỏ sót...")
        missing = run(missing, 3)
    if missing:
        print(f"Vẫn bỏ sót: {', '.join(missing)}", file=sys.stderr)

    print()
    got = {w: state["audited"][w] for w in words if w in state["audited"]}
    for w, v in sorted(got.items(), key=lambda kv: kv[1]["score"]):
        print(f"{v['score']:>2}  {w}  {'; '.join(v['issues'])}")
    if got:
        print(f"\nTrung bình đợt này: {sum(v['score'] for v in got.values())/len(got):.2f}")


def report(cards, state):
    done = state["audited"]
    if not done:
        print("Chưa chấm từ nào.")
        return
    scores = [v["score"] for v in done.values()]
    print(f"Đã chấm {len(done)}/{len(cards)} từ, điểm trung bình {sum(scores)/len(scores):.2f}")
    for lo, hi in [(0, 4), (4, 7), (7, 9), (9, 11)]:
        c = len([s for s in scores if lo <= s < hi])
        print(f"  {lo}-{hi-1}: {c}")
    worst = sorted(done.items(), key=lambda kv: kv[1]["score"])[:15]
    print("\nTệ nhất:")
    for w, v in worst:
        print(f"  {v['score']:>2}  {w}: {'; '.join(v['issues']) or '-'}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("count", nargs="?", type=int, default=50)
    ap.add_argument("--threshold", type=int, default=8)
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--src", choices=["all", "pack", "saved"], default="all",
                    help="chỉ chấm từ trong vocab pack hoặc chỉ saved words")
    ap.add_argument("--fix", action="store_true", help="sửa thẻ điểm thấp")
    ap.add_argument("--auto", action="store_true",
                    help="chấm, sửa thẻ dưới ngưỡng, rồi chấm lại các thẻ vừa sửa")
    ap.add_argument("--skip", metavar="W1,W2",
                    help="đánh dấu bỏ qua các từ này khi chấm lại và khi sửa")
    ap.add_argument("--force", action="store_true",
                    help="sửa saved word kể cả khi NTranslate đang chạy")
    a = ap.parse_args()

    state = load_state()
    if a.skip:
        for w in [x.strip() for x in a.skip.split(",") if x.strip()]:
            entry = state["audited"].setdefault(w, {"score": 0, "issues": [], "src": "saved",
                                                    "at": "", "round": 0})
            entry["skip"] = True
            print(f"bỏ qua: {w}")
        save_state(state)
        return

    if a.fix:
        fix(state, a.count, a.threshold, a.src, a.force)
        return

    cards = load_cards()
    if a.report:
        report(cards, state)
        return

    words, mode = pick(cards, state, a.count, a.threshold, a.src)
    if not words:
        print("Không còn từ nào cần chấm.")
        return
    audit(cards, state, words, mode)

    if a.auto:
        fixed = fix(state, a.count, a.threshold, a.src, a.force)
        if fixed:
            print("\nChấm lại các thẻ vừa sửa...")
            audit(cards := load_cards(), state, [w for w in fixed if w in cards], "sau khi sửa")

    print(f"State: {STATE}")


if __name__ == "__main__":
    main()
