# Об'єднання блоків rmflash.py: середнє, медіана, 95% довірчі інтервали (bootstrap), різниці між варіантами.
# python3 latpool.py A.raw B.raw ...   (перший файл — база для різниць)
import random, statistics, sys
random.seed(1)
def boot(xs, f, k=4000):
    vals = sorted(f(random.choices(xs, k=len(xs))) for _ in range(k))
    return vals[int(0.025 * k)], vals[int(0.975 * k)]
data = {p: [float(l) for l in open(p) if l.strip()] for p in sys.argv[1:]}
base = sys.argv[1]
for p, xs in data.items():
    m, md = statistics.mean(xs), statistics.median(xs)
    lo, hi = boot(xs, statistics.mean)
    line = f"{p}: n={len(xs)} mean={m:.1f} [{lo:.1f}..{hi:.1f}] median={md:.1f} sd={statistics.pstdev(xs):.1f}"
    if p != base:
        b = data[base]
        diffs = sorted(statistics.mean(random.choices(xs, k=len(xs))) - statistics.mean(random.choices(b, k=len(b))) for _ in range(4000))
        line += f"  vs {base}: {m - statistics.mean(b):+.1f} [{diffs[100]:+.1f}..{diffs[3899]:+.1f}]"
    print(line)
