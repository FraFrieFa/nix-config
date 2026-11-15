import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:3])
ignore = {"headset:0f"}
for k in a:
    if a[k] != b.get(k) and k not in ignore and (a[k] or "")[9:11] == "00":
        print(f"{k}\n  {sys.argv[1]}: {a[k][:47]}\n  {sys.argv[2]}: {(b.get(k) or '')[:47]}")
