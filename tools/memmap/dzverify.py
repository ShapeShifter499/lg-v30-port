import sys, os
sys.path.insert(0, "/data/buildcache/kdztools")
sys.argv = ["undz.py"]
import undz
f = undz.UNDZFile(sys.stdin.readline().strip())
n = ok = 0
for c in f.chunks:
    c.extract()      # decompresses and exits on any MD5 mismatch
    n += 1
print(f"{n} chunks, all data MD5s match their headers")
