"""Spike: how fast can Jev judge a real corpus? Concurrency, rate limits, and item-packing."""
import asyncio, json, time, urllib.request, statistics
from concurrent.futures import ThreadPoolExecutor
from typesafe_sdk import AsyncTypeSafeClient, Choice, Noul, Score

def get(url):
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.load(r)

ids = get("https://hacker-news.firebaseio.com/v0/topstories.json")[:96]
with ThreadPoolExecutor(24) as ex:
    items = [i for i in ex.map(lambda i: get(f"https://hacker-news.firebaseio.com/v0/item/{i}.json"), ids) if i and i.get("title")]
titles = [i["title"] for i in items]
print(f"fetched {len(titles)} HN titles")

PROFILE = ("The reader cares about: local-first software, on-device ML on Apple Silicon, game modding, "
           "music composition tools, developer tools. Not interested in: crypto, startup funding news, politics.")

def questions(path="title"):
    return {
        "relevance": Score(
            instructions=f"How relevant `{path}` is to the reader described in `reader`",
            criteria=["Unrelated to the reader's interests", "Loosely adjacent to an interest",
                      "Clearly relevant to one interest", "Squarely in the reader's core interests"]),
        "depth": Score(
            instructions=f"How technically deep the piece behind `{path}` is likely to be",
            criteria=["Headline news or an announcement", "General discussion or opinion",
                      "Concrete technical detail", "Deep technical work or original research"]),
        "hype": Noul(instructions=f"`{path}` is promotional or hype-driven rather than informative"),
        "kind": Choice(instructions=f"What kind of post `{path}` is", criteria={
            "project": "Something a person built and is showing",
            "news": "A news event or company announcement",
            "essay": "An opinion piece, essay or blog reflection",
            "research": "A paper, study or deep technical write-up",
            "question": "A question or discussion prompt"}),
    }

async def one_per_request(client, conc):
    sem = asyncio.Semaphore(conc)
    errors, lat, toks, out = [], [], 0, {}
    async def run(t):
        nonlocal toks
        async with sem:
            t0 = time.perf_counter()
            try:
                r = await client.system_one(state={"reader": PROFILE, "title": t}, questions=questions())
                lat.append((time.perf_counter() - t0) * 1000)
                toks += r.usage.input_tokens
                out[t] = r.answers
            except Exception as e:
                errors.append(type(e).__name__)
    t0 = time.perf_counter()
    await asyncio.gather(*(run(t) for t in titles))
    wall = time.perf_counter() - t0
    print(f"  conc={conc:3}  {len(out):3} ok  {len(errors)} err {set(errors) or ''}  wall {wall:5.1f}s  "
          f"{len(out)/wall:5.1f} items/s  p50 {statistics.median(lat):.0f} ms  tokens {toks}")
    return out

async def packed(client, per, conc=16):
    """Several items share one request; each gets its own questions pointing at its path."""
    sem = asyncio.Semaphore(conc)
    out, errors, toks = {}, [], 0
    chunks = [titles[i:i + per] for i in range(0, len(titles), per)]
    async def run(chunk):
        nonlocal toks
        qs = {}
        for i, _ in enumerate(chunk):
            for k, q in questions(f"items[{i}]").items():
                qs[f"{k}__{i}"] = q
        async with sem:
            try:
                r = await client.system_one(state={"reader": PROFILE, "items": chunk}, questions=qs)
                toks += r.usage.input_tokens
                for i, t in enumerate(chunk):
                    out[t] = {k: r.answers[f"{k}__{i}"] for k in ("relevance", "depth", "hype", "kind")}
            except Exception as e:
                errors.append(f"{type(e).__name__}: {str(e)[:80]}")
    t0 = time.perf_counter()
    await asyncio.gather(*(run(c) for c in chunks))
    wall = time.perf_counter() - t0
    print(f"  packed x{per:2}  {len(out):3} ok  {len(errors)} err {errors[:1] or ''}  wall {wall:5.1f}s  "
          f"{len(out)/max(wall,1e-9):5.1f} items/s  tokens {toks}")
    return out

async def main():
    client = AsyncTypeSafeClient()
    print("one item per request:")
    base = None
    for conc in (8, 32, 96):
        res = await one_per_request(client, conc)
        base = base or res
    print("packed requests:")
    for per in (8, 24):
        res = await packed(client, per)
        both = [t for t in res if t in base]
        if both:
            agree = sum(res[t]["kind"].choice == base[t]["kind"].choice for t in both) / len(both)
            drift = statistics.mean(abs(res[t]["relevance"].score - base[t]["relevance"].score) for t in both)
            print(f"      vs single: kind agreement {agree:.0%}, mean |relevance drift| {drift:.2f} (scale 0-3)")
    print("\nTOP 8 by relevance:")
    for t in sorted(base, key=lambda t: -base[t]["relevance"].score)[:8]:
        a = base[t]
        print(f"  {a['relevance'].score:.2f} rel  {a['depth'].score:.2f} depth  hype {a['hype'].noul:.2f}  {a['kind'].choice:8} | {t[:70]}")
    print("BOTTOM 4:")
    for t in sorted(base, key=lambda t: base[t]["relevance"].score)[:4]:
        print(f"  {base[t]['relevance'].score:.2f} rel | {t[:70]}")

asyncio.run(main())
