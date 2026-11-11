#!/usr/bin/env python3
"""Generate random test vectors + golden results for tb_ecg_accelerator.v.
Golden model mirrors the RTL arithmetic exactly (INT8 x INT8, INT32 acc,
ReLU, round(sum*127/MAX) with clamp at 127, argmax with lowest-index ties)."""
import random, sys
N   = int(sys.argv[1]) if len(sys.argv) > 1 else 20
MAX = 99580
random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
r8 = lambda: random.randint(-128, 127)

w1 = [r8() for _ in range(64*128)]
b1 = [random.randint(-60000, 60000) for _ in range(64)]
w2 = [r8() for _ in range(5*64)]
b2 = [random.randint(-20000, 20000) for _ in range(5)]
x  = [r8() for _ in range(N*128)]

def h(v, bits): return format(v & ((1 << bits) - 1), '0%dx' % (bits // 4))
def dump(name, vals, bits):
    open(name, 'w').write('\n'.join(h(v, bits) for v in vals) + '\n')

dump('w1.hex', w1, 8); dump('b1.hex', b1, 32)
dump('w2.hex', w2, 8); dump('b2.hex', b2, 32); dump('x.hex', x, 8)

act_all, cls_all, score_all = [], [], []
for n in range(N):
    xs = x[n*128:(n+1)*128]
    act = []
    for j in range(64):
        s = b1[j] + sum(xs[i]*w1[j*128+i] for i in range(128))
        act.append(0 if s <= 0 else min(127, (s*127 + MAX//2)//MAX))
    sc = [b2[k] + sum(act[i]*w2[k*64+i] for i in range(64)) for k in range(5)]
    c = max(range(5), key=lambda k: (sc[k], -k))
    act_all += act; cls_all.append(c); score_all.append(sc[c])

dump('exp_act.hex', act_all, 8)
dump('exp_class.hex', cls_all, 4)
dump('exp_score.hex', score_all, 32)
print('vectors', N, 'classes', cls_all,
      'act: zeros', act_all.count(0), 'sat', act_all.count(127),
      'mid', len(act_all) - act_all.count(0) - act_all.count(127))
