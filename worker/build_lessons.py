import json, hashlib, os, glob
ROOT = os.path.dirname(os.path.abspath(__file__))
GROUPS = {"tier1": "Tier 1 - Core prompts", "tier2": "Tier 2 - Full prompts", "tier3": "Tier 3 - Multi-turn"}
lessons, t = [], 812800000
for path in sorted(glob.glob(os.path.join(ROOT, "lessons-src", "tier*.json"))):
    group = GROUPS[os.path.basename(path)[:-5]]
    for s in json.load(open(path)):
        for k in ("title", "scenario", "words", "topic", "pattern", "en", "vi"):
            assert s.get(k), f"{s.get('title')}: missing {k}"
        assert len(s["en"]) == len(s["vi"]), f"{s['title']}: en/vi count differ"
        assert 15 <= len(s["en"]) <= 20, f"{s['title']}: {len(s['en'])} lines"
        assert len(s["words"]) == 3 and not any('"' in l for l in s["en"] + s["vi"]), s["title"]
        text = f"Topic: {s['topic']}\n\n" + "\n".join(s["en"]) + "\n\n" + "\n".join(s["vi"]) + f"\n\nPrompt pattern: {s['pattern']}"
        lessons.append({"words": s["words"], "text": text, "promptVersion": "7", "generatedAt": t,
                        "title": s["title"], "scenario": s["scenario"], "group": group, "count": 0})
        t += 1000
out = os.path.join(ROOT, "ntranslate-english-lessons.json")
json.dump(lessons, open(out, "w"), ensure_ascii=False, indent=2)
json.loads(open(out).read())
cfg = json.load(open(os.path.expanduser("~/Library/Application Support/NTranslate/config.json")))
weave = os.path.join(os.path.expanduser(cfg.get("historyDirectory") or "~/Library/Application Support/NTranslate"), "weave")
os.makedirs(weave, exist_ok=True)
new = upd = 0
for l in lessons:
    f = os.path.join(weave, hashlib.sha256(l["text"].encode()).hexdigest() + ".json")
    item = dict(l)
    if os.path.exists(f):
        old = json.load(open(f)); upd += 1
        for k in ("count", "isDone"):
            if k in old: item[k] = old[k]
    else:
        new += 1
    open(f, "w", encoding="utf-8").write(json.dumps(item, ensure_ascii=False, separators=(",", ":")))
print(f"{len(lessons)} lessons -> {out}\ninstalled to {weave}: {new} new, {upd} updated")
