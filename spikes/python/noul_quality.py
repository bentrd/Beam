"""Spike: is Noul trustworthy on short, sarcastic, multilingual feedback? Hand-labelled, 3 propositions."""
import asyncio, statistics
from typesafe_sdk import AsyncTypeSafeClient, Noul

# (text, price_complaint, reports_bug, wants_to_leave)
DATA = [
 ("Way too expensive for what it does.", 1, 0, 0),
 ("Love it, worth every penny.", 0, 0, 0),
 ("Crashes every time I open a PDF. Fix this.", 0, 1, 0),
 ("Oh great, another price hike. Exactly what I wanted.", 1, 0, 0),
 ("Cancelling my subscription tonight. Done.", 0, 0, 1),
 ("Trop cher depuis la dernière mise à jour, je vais voir ailleurs.", 1, 0, 1),
 ("L'appli plante dès que j'importe un fichier.", 0, 1, 0),
 ("Franchement génial, rien à redire.", 0, 0, 0),
 ("Je résilie, 15 euros par mois c'est du vol.", 1, 0, 1),
 ("Sync is broken since 4.2, lost two notes.", 0, 1, 0),
 ("it's fine i guess", 0, 0, 0),
 ("Sure, $20/month for a notes app. Totally reasonable. /s", 1, 0, 0),
 ("Demasiado caro y además se cierra solo.", 1, 1, 0),
 ("Would pay double honestly.", 0, 0, 0),
 ("Switched to a competitor last week, no regrets.", 0, 0, 1),
 ("The new pricing is fair, the old one was too cheap to be sustainable.", 0, 0, 0),
 ("Not a bug exactly, but the export button does nothing on my Mac.", 0, 1, 0),
 ("Support replied in 5 minutes, impressive.", 0, 0, 0),
 ("If you raise prices again I'm out.", 1, 0, 1),
 ("Dark mode when??", 0, 0, 0),
 ("Das Abo ist mir zu teuer geworden, ich kündige.", 1, 0, 1),
 ("Freezes on launch after the update. Reinstalled twice.", 0, 1, 0),
 ("Best purchase this year.", 0, 0, 0),
 ("Refund please. Doesn't work and costs a fortune.", 1, 1, 1),
 ("I keep coming back to it, nothing else is as fast.", 0, 0, 0),
 ("pas mal mais le prix pique un peu", 1, 0, 0),
 ("Can't log in, spinner forever.", 0, 1, 0),
 ("My team is moving off this next quarter.", 0, 0, 1),
 ("Cheap, fast, reliable. Pick three.", 0, 0, 0),
 ("Wow, it deleted my data. Five stars for the surprise.", 0, 1, 0),
]
Q = {
 "price": Noul(instructions="The writer complains that the product costs too much"),
 "bug":   Noul(instructions="The writer reports that something in the product is broken or malfunctioning"),
 "leave": Noul(instructions="The writer says they have left, are leaving, or intend to stop using the product"),
}
KEYS = ["price", "bug", "leave"]

async def main():
    c = AsyncTypeSafeClient()
    sem = asyncio.Semaphore(16)
    async def run(t):
        async with sem:
            return (await c.system_one(state={"feedback": t}, questions=Q)).answers
    res = await asyncio.gather(*(run(d[0]) for d in DATA))
    total = wrong = unsure = 0
    bands = {"sure": [0, 0], "unsure": [0, 0]}
    misses = []
    for d, a in zip(DATA, res):
        for i, k in enumerate(KEYS):
            p, truth = a[k].noul, d[i + 1]
            total += 1
            band = "unsure" if 0.25 < p < 0.75 else "sure"
            ok = (p >= 0.5) == bool(truth)
            bands[band][0] += 1
            bands[band][1] += ok
            if not ok:
                wrong += 1
                misses.append((k, truth, round(p, 2), d[0]))
    print(f"accuracy {1 - wrong/total:.1%} over {total} judgments")
    for b, (n, ok) in bands.items():
        print(f"  {b:6}: {n:3} judgments, {ok/n:.1%} correct" if n else f"  {b}: none")
    print("misses:")
    for m in misses:
        print("  ", m)

asyncio.run(main())
