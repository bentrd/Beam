"""Spike: can a user-typed phrase become a usable graded lens without a hand-written rubric?
Compares (A) hand-written Score rubric, (B) templated Score from the phrase, (C) Noul from the phrase."""
import asyncio, json, statistics, urllib.request
from concurrent.futures import ThreadPoolExecutor
from typesafe_sdk import AsyncTypeSafeClient, Noul, Score

def get(u):
    with urllib.request.urlopen(u, timeout=15) as r: return json.load(r)

ids = get("https://hacker-news.firebaseio.com/v0/topstories.json")[:90]
with ThreadPoolExecutor(24) as ex:
    items = [i for i in ex.map(lambda i: get(f"https://hacker-news.firebaseio.com/v0/item/{i}.json"), ids) if i and i.get("title")]
titles = [i["title"] for i in items]

def template(x):
    return [f"Not at all {x}", f"Slightly {x}", f"Clearly {x}", f"Extremely {x}"]

LENSES = {
  "technically deep": ["Headline news or an announcement", "General discussion or opinion",
                       "Concrete technical detail", "Deep technical work or original research"],
  "about business or money": ["Nothing to do with business or money", "Mentions a company in passing",
                       "Mostly about a company, market or deal", "Entirely about funding, revenue, pricing or acquisitions"],
  "fun or playful": ["Serious and dry", "Neutral in tone", "Has a playful or curious angle", "Pure fun: a game, toy, joke or delightful hack"],
}

def qs():
    q = {}
    for i, (phrase, rubric) in enumerate(LENSES.items()):
        q[f"A{i}"] = Score(instructions=f"How {phrase} `title` is", criteria=rubric)
        q[f"B{i}"] = Score(instructions=f"How {phrase} `title` is", criteria=template(phrase))
        q[f"C{i}"] = Noul(instructions=f"`title` is {phrase}")
    return q

def ranks(v):
    order = sorted(range(len(v)), key=lambda i: v[i]); r = [0]*len(v)
    for pos, i in enumerate(order): r[i] = pos
    return r
def spearman(a, b):
    ra, rb = ranks(a), ranks(b); n = len(a)
    return 1 - 6*sum((x-y)**2 for x, y in zip(ra, rb)) / (n*(n*n-1))

async def main():
    c = AsyncTypeSafeClient(); sem = asyncio.Semaphore(32)
    async def run(t):
        async with sem: return (await c.system_one(state={"title": t}, questions=qs())).answers
    res = await asyncio.gather(*(run(t) for t in titles))
    print(f"{len(titles)} titles, 9 questions each, one request per title\n")
    for i, phrase in enumerate(LENSES):
        A = [r[f"A{i}"].score/3 for r in res]; B = [r[f"B{i}"].score/3 for r in res]; C = [r[f"C{i}"].noul for r in res]
        mid = lambda v: sum(0.1 < x < 0.9 for x in v)/len(v)
        print(f"'{phrase}'")
        print(f"   templated Score vs hand rubric : spearman {spearman(A,B):.2f}   graded (0.1-0.9): {mid(B):.0%}")
        print(f"   Noul            vs hand rubric : spearman {spearman(A,C):.2f}   graded (0.1-0.9): {mid(C):.0%}")
        top = sorted(range(len(titles)), key=lambda k: -B[k])[:3]
        for k in top: print(f"      B top: {B[k]:.2f}  {titles[k][:64]}")
asyncio.run(main())
