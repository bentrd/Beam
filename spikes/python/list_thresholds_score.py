"""Risk 1 eval, step 2: precision/recall of list bands per frame and threshold, from hand labels over the pooled candidates.
Pooled evaluation: anything outside the pool is assumed not relevant (standard TREC-style pooling)."""
import json
d = json.load(open("/tmp/claude-501/list_eval.json"))
items, scores, frames = d["items"], d["scores"], d["frames"]
mlx = {k for k, i in enumerate(items) if i["source"] == "mlx"}
REL = {0: {8, 149, 72} | mlx, 1: {25, 17}, 2: set(mlx), 4: {1, 33, 90, 104, 19}, 5: {59}, 6: set(),
       7: {28, 25, 79, 20, 17, 10, 45, 87}, 8: {120, 99, 112, 118, 132, 94, 33, 136, 116, 0}, 9: {65}}
SKIP = {8: {119, 71}}          # genuinely unknowable from the title
print(f"{len(items)} items · {len(REL)} labelled sentences · {sum(len(v) for v in REL.values())} relevant pairs\n")
print(f"{'frame':9} {'found>=':>7} | {'found P':>8} {'found R':>8} {'n':>4} | unsure band → {'P':>5} {'n':>4} | found+unsure R")
for f in frames:
    for hi in (0.5, 0.6, 0.7, 0.75):
        lo = 0.25
        tp = fp = fn = utp = ufp = 0
        for qi, rel in REL.items():
            skip = SKIP.get(qi, set())
            for k, s in enumerate(scores):
                if k in skip: continue
                v = s[f"{f}|{qi}"]; r = k in rel
                if v >= hi: tp += r; fp += (not r)
                elif v >= lo: utp += r; ufp += (not r)
                if r and v < hi: fn += 1
        P = tp / max(tp + fp, 1); R = tp / max(tp + fn, 1)
        UP = utp / max(utp + ufp, 1); RR = (tp + utp) / max(tp + fn, 1)
        print(f"{f:9} {hi:7.2f} | {P:8.0%} {R:8.0%} {tp+fp:4} | {'':14} {UP:5.0%} {utp+ufp:4} | {RR:6.0%}")
    print()
print("per-sentence, frame 'about', found>=0.60 / unsure 0.25-0.60:")
for qi, rel in REL.items():
    col = [s[f"about|{qi}"] for s in scores]
    found = [k for k, v in enumerate(col) if v >= 0.6]; unsure = [k for k, v in enumerate(col) if 0.25 <= v < 0.6]
    print(f"  “{d['queries'][qi][:40]:40}” relevant {len(rel):2} | found {len(found):2} ({sum(k in rel for k in found)} right) | unsure {len(unsure):2} ({sum(k in rel for k in unsure)} right)")
