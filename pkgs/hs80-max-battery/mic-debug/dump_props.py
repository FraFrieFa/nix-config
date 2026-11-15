import json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import hs80_max_battery as h

out = sys.argv[1]
dev = h.vendor_device(h.find_receivers())
fd = os.open(dev.path, os.O_RDWR)
result = {}
try:
    if not h.wake_device(fd):
        sys.exit("headset not connected")
    for ep_name, ep in (("receiver", h.RECEIVER_ENDPOINT), ("headset", h.HEADSET_ENDPOINT)):
        for prop in range(256):
            h.flush_reports(fd, max_seconds=0.02)
            os.write(fd, h.v2_request(ep, prop))
            r = h.read_report(fd, 0.3)
            result[f"{ep_name}:{prop:02x}"] = r.hex(" ") if r else None
finally:
    os.close(fd)
json.dump(result, open(out, "w"), indent=1)
print(sum(v is not None for v in result.values()), "responses ->", out)
