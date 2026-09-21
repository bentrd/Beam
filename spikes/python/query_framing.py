"""Spike: the phrasing lottery. Realistic typed queries x 3 framing templates over the live HN front page."""
import asyncio, json, urllib.request
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlparse
from typesafe_sdk import AsyncTypeSafeClient, Noul

def get(u):
    with urllib.request.urlopen(u, timeout=15) as r: return json.load(r)
ids = get("https://hacker-news.firebaseio.com/v0/topstories.json")[:120]
with ThreadPoolExecutor(32) as ex:
    raw = [i for i in ex.map(lambda i: get(f"https://hacker-news.firebaseio.com/v0/item/{i}.json"), ids) if i and i.get("title")]
items = [{"title": i["title"], "site": urlparse(i.get("url", "")).netloc.replace("www.", "") or "news.ycombinator.com"} for i in raw]

QUERIES = ["on-device ML on Apple Silicon", "game modding", "rust", "is AI making programmers worse?",
           "trucs sur la vie privée et la surveillance", "retro computing", "new programming languages",
           "things I can build this weekend", "not about AI", "security vulnerabilities"]
FRAMES = {
  "about":    lambda q: f"This item is about: {q}",
  "searcher": lambda q: f"Someone who searched for “{q}” would want to read this item",
  "relevant": lambda q: f"This item is relevant to the search query “{q}”",
}

async def main():
    c = AsyncTypeSafeClient(); sem = asyncio.Semaphore(48)
    async def run(item):
        qs = {f"{f}|{qi}": Noul(instructions=fn(q)) for qi, q in enumerate(QUERIES) for f, fn in FRAMES.items()}
        async with sem:
            return (await c.system_one(state={"item": item}, questions=qs)).answers
    import time; t0 = time.perf_counter()
    res = await asyncio.gather(*(run(i) for i in items))
    print(f"{len(items)} items x {len(QUERIES)*len(FRAMES)} questions in {time.perf_counter()-t0:.1f}s\n")
    for qi, q in enumerate(QUERIES):
        print(f"■ “{q}”")
        tops = {}
        for f in FRAMES:
            col = [r[f"{f}|{qi}"].noul for r in res]
            order = sorted(range(len(col)), key=lambda k: -col[k])
            found = sum(x >= 0.75 for x in col); unsure = sum(0.25 < x < 0.75 for x in col)
            tops[f] = set(order[:8])
            print(f"   {f:9} found {found:3} unsure {unsure:3} | " + " · ".join(f"{col[k]:.2f} {items[k]['title'][:34]}" for k in order[:3]))
        fs = list(FRAMES)
        print(f"   top-8 overlap: about∩searcher {len(tops[fs[0]]&tops[fs[1]])}/8   about∩relevant {len(tops[fs[0]]&tops[fs[2]])}/8   searcher∩relevant {len(tops[fs[1]]&tops[fs[2]])}/8")
asyncio.run(main())
