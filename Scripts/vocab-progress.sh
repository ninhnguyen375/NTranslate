#!/bin/bash
# Progress of a vocabulary pack run. Reads the work file, which is the source of truth:
# the generator appends exactly one line per finished word.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, os
work = 'Scripts/.vocab-work/en-vi.jsonl'
if not os.path.exists(work):
    print('No run yet.'); raise SystemExit
lines = []
for raw in open(work):
    try: lines.append(json.loads(raw))
    except ValueError: pass          # a half-written final line
total = sum(1 for l in open('Scripts/data/wordlist.txt')
            if l.strip() and not l.startswith('#'))
ok = [l for l in lines if l['status'] == 'ok']
err = [l for l in lines if l['status'] == 'error']
pending = total - len({l['w'].lower() for l in ok})
print(f"{len(ok)}/{total} xong · {len(err)} loi · {pending} con lai")
if ok:   print("gan nhat:", ", ".join(l['w'] for l in ok[-6:]))
if err:  print("loi cuoi:", err[-1]['w'], "-", err[-1]['err'][:60])
PY
