#!/usr/bin/env python3
"""Set whitelisted fields on a Streamer input config: read full object, change fields, PUT, re-read.
Usage: streamer_set.py ID key=json_value [key=json_value ...]   (keys: input_v4l2_resolution, h264_profile, h264_bitrate, h264_i_frame_period)"""
import json, sys, time, urllib.request
BASE = "http://192.168.13.21/api/"
ALLOWED = {"input_v4l2_resolution", "h264_profile", "h264_level", "h264_bitrate", "h264_i_frame_period"}
def get(path):
    return json.load(urllib.request.urlopen(BASE + path, timeout=5))
sid = int(sys.argv[1]); changes = {}
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    if k not in ALLOWED: sys.exit(f"field {k} not allowed")
    changes[k] = json.loads(v)
cfg = next(c for c in get("v3/streamer/configs")["configs"] if c["id"] == sid)
before = {k: cfg.get(k) for k in changes}
cfg.update(changes)
req = urllib.request.Request(BASE + f"v3/streamer/{sid}/config", data=json.dumps(cfg).encode(), method="PUT",
                             headers={"Content-Type": "application/json"})
resp = urllib.request.urlopen(req, timeout=10); print("PUT", resp.status)
time.sleep(4)
after = {k: next(c for c in get("v3/streamer/configs")["configs"] if c["id"] == sid).get(k) for k in changes}
print("before:", before); print("after: ", after)
for _ in range(10):
    st = get("v3/streamer/statuses").get(str(sid), {}).get("runtime") or {}
    if st.get("live"): break
    time.sleep(1)
print("status:", st.get("live"), st.get("input"))
