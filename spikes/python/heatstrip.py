"""Spike: 'Cmd-F for meaning' on a real legal document. Every paragraph judged against 6 propositions."""
import asyncio, re, time, urllib.request, html
from html.parser import HTMLParser
from typesafe_sdk import AsyncTypeSafeClient, Noul

URL = "https://docs.github.com/en/site-policy/github-terms/github-terms-of-service"
req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0"})
raw = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "ignore")

class P(HTMLParser):
    def __init__(s):
        super().__init__(); s.units = []; s.buf = []; s.tag = None; s.heading = ""; s.skip = 0
    def handle_starttag(s, t, a):
        if t in ("script", "style", "nav", "header", "footer"): s.skip += 1
        if t in ("p", "li", "h1", "h2", "h3", "h4") and not s.skip: s.tag = t; s.buf = []
    def handle_endtag(s, t):
        if t in ("script", "style", "nav", "header", "footer"): s.skip = max(0, s.skip - 1)
        if t == s.tag:
            text = re.sub(r"\s+", " ", "".join(s.buf)).strip()
            if t.startswith("h"): s.heading = text
            elif len(text) > 60: s.units.append((s.heading, text))
            s.tag = None
    def handle_data(s, d):
        if s.tag and not s.skip: s.buf.append(d)
p = P(); p.feed(raw); units = p.units
words = sum(len(u[1].split()) for u in units)
print(f"{len(units)} paragraphs, {words} words (~{words//280} pages)")

LENSES = {
 "terminate": "This passage says the company may suspend or terminate the user's account",
 "liability": "This passage limits the company's liability or disclaims warranties",
 "law":       "This passage says which jurisdiction's law governs disputes",
 "pay":       "This passage obliges the user to pay money or describes billing",
 "content":   "This passage gives the company rights over content the user uploads",
 "refund":    "This passage says whether the user can get a refund",
}
Q = {k: Noul(instructions=v) for k, v in LENSES.items()}

async def sweep(with_heading):
    c = AsyncTypeSafeClient(); sem = asyncio.Semaphore(64); toks = 0; first = []
    t0 = time.perf_counter()
    async def run(i, h, t):
        nonlocal toks
        state = {"section": h, "passage": t} if with_heading else {"passage": t}
        async with sem:
            r = await c.system_one(state=state, questions=Q)
            toks += r.usage.input_tokens
            if len(first) < 1: first.append(time.perf_counter() - t0)
            return r.answers
    res = await asyncio.gather(*(run(i, h, t) for i, (h, t) in enumerate(units)))
    return res, time.perf_counter() - t0, toks, first[0]

async def main():
    res, wall, toks, first = await sweep(True)
    n = len(units) * len(Q)
    print(f"\n{n} judgments in {wall:.1f}s (first result {first*1000:.0f} ms) · {toks} tokens · ${toks*0.042/1e6:.4f}\n")
    for k, sentence in LENSES.items():
        col = [r[k].noul for r in res]
        hot = sum(x >= 0.5 for x in col); unsure = sum(0.25 < x < 0.75 for x in col)
        print(f"■ {sentence}\n   {hot} hot · {unsure} unsure · {len(col)-hot} dark")
        for i in sorted(range(len(col)), key=lambda i: -col[i])[:3]:
            print(f"   {col[i]:.2f} [{units[i][0][:28]}] {units[i][1][:118]}")
    # recall sanity check: paragraphs containing an unmistakable keyword should be hot
    checks = {"law": r"governed by|laws of the State", "refund": r"refund", "terminate": r"suspend or terminate|terminate your"}
    print("\nkeyword recall check:")
    for k, pat in checks.items():
        idx = [i for i, u in enumerate(units) if re.search(pat, u[1], re.I)]
        got = sum(res[i][k].noul >= 0.5 for i in idx)
        print(f"   {k:10} {got}/{len(idx)} keyword paragraphs are hot  " + " ".join(f"{res[i][k].noul:.2f}" for i in idx))
    res2, wall2, toks2, _ = await sweep(False)
    flips = sum((a[k].noul >= 0.5) != (b[k].noul >= 0.5) for a, b in zip(res, res2) for k in Q)
    print(f"\nwithout section heading: {wall2:.1f}s · {toks2} tokens · {flips}/{n} judgments flip side")
asyncio.run(main())
