#!/usr/bin/env python3
# usage: bin/portal-proto.py job|session|error <base64>   ポータル (isuxportal) の protobuf の応答を JSON にする (bin/portal-bench.sh が使う)
#   job:     GetBenchmarkJobResponse / EnqueueBenchmarkJobResponse → {id,status,finished,passed,score,raw,deduction,reason,stdout,stderr}
#   session: GetCurrentSessionResponse → [{id,number,public_ip,private_ip,status}] (負荷をかける先の候補)
#   error:   isuxportal.proto.Error → {code,name,message}
import base64, json, sys

def varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1; r |= (c & 0x7f) << s; s += 7
        if c < 0x80: return r, i

def fields(b):
    out, i = {}, 0
    while i < len(b):
        k, i = varint(b, i); f, w = k >> 3, k & 7
        if w == 0: v, i = varint(b, i)
        elif w == 2:
            l, i = varint(b, i); v = b[i:i + l]; i += l
        elif w == 1: v = b[i:i + 8]; i += 8
        elif w == 5: v = b[i:i + 4]; i += 4
        else: raise ValueError(f"wire type {w}")
        out.setdefault(f, []).append(v)
    return out

def one(d, f, default=None): return d.get(f, [default])[-1]
def s(v): return v.decode("utf-8", "replace") if isinstance(v, bytes) else (v or "")
def i64(v): return v - (1 << 64) if v and v >= 1 << 63 else (v or 0)

STATUS = {0: "PENDING", 1: "RUNNING", 2: "ERRORED", 3: "CANCELLED", 4: "FINISHED"}

def job(b):
    j = fields(one(fields(b), 1, b""))
    r = fields(one(j, 18, b""))
    br = fields(one(r, 4, b"")); ex = fields(one(r, 5, b""))
    return {"id": one(j, 1, 0), "target_id": one(j, 3, 0), "status": STATUS.get(one(j, 4, 0), str(one(j, 4, 0))),
            "finished": bool(one(r, 1, 0)), "passed": bool(one(r, 2, 0)), "score": i64(one(r, 3, 0)),
            "raw": i64(one(br, 1, 0)), "deduction": i64(one(br, 2, 0)),
            "reason": s(one(ex, 1)), "stdout": s(one(ex, 2)), "stderr": s(one(ex, 3))}

def session(b):
    out = []
    for c in fields(b).get(5, []):
        d = fields(c)
        out.append({"id": one(d, 7, 0), "number": one(d, 3, 0), "public_ip": s(one(d, 4)), "private_ip": s(one(d, 5)), "status": one(d, 6, 0)})
    return out

def error(b):
    d = fields(b)
    return {"code": one(d, 1, 0), "name": s(one(d, 2)), "message": s(one(d, 3))}

kind, data = sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else sys.stdin.read().strip()
b = base64.b64decode(data + "=" * (-len(data) % 4))
print(json.dumps({"job": job, "session": session, "error": error}[kind](b), ensure_ascii=False))
