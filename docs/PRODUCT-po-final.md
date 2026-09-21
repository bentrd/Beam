Gate: this is a proposal for Ben, relayed from his request to be consulted first. No build step, evals included, should follow without his explicit yes.

PART 1: FINAL SPEC

1. **One line + the 10-second aha**

Ben gets six lines and a static mock (image; Figma connector unauthorised):

1. Nothing is built, evals included, until you say yes.
2. Beam ranks everything you follow against one plain sentence, then opens each article with the matching paragraphs already lit.
3. Aha: type "on-device ML on Apple Silicon", Return: solid-dot rows fill the list in two seconds. Return again: a clean article, three paragraphs tinted.
4. Decided unless you veto: serif body; text-only reader; "nothing" rows hidden; no digest; no read/unread.
5. Starter sources: Hacker News, MLX GitHub releases, Apple Machine Learning Research?
6. May Beam pre-judge the top three results so they open lit? Paragraphs of unopened articles reach TypeSafe.

2. **First 60 seconds**

Three removable starter sources are fetching; within 5 s Beam is a quiet chronological reader, no key needed. Return in the field ("Describe what you want to read") drops one inline panel: disclosure, secure field, "Get a key" link. Paste, Return: a constant-string call validates the key and the waiting sentence runs. Later launches restore selection and scroll position.

3. **Object model**

- Source: feed URL, title, kind (from the host: icon, fetch and reader rule), last error. One feed parser plus an Algolia JSON adapter for HN.
- Item: identity (GUID, else URL), title, 300-character snippet, URL, date, opened.
- Pin: a saved sentence, last viewed; max 9, one per Cmd-digit.
- Article: an item's passages, or failed.
- Judgment: probability for one (text, framed sentence).

Persisted: all of it plus daily tokens sent, one SQLite file; key in the login Keychain; items purge after a year.
Cache key: sha256(text) + sha256(framed sentence) + model id, so frame and title edits invalidate themselves.

4. **Screens**

- Sidebar (glass): All Items; Pins (sentence; count of found items new since last viewed; no header when empty); Sources (kind symbol, title; failing: warning glyph, error tooltip, Retry in context menu); "+".
- Toolbar (glass): search field with a trailing pin glyph: filled when pinned, disabled at nine ("Nine pins maximum").
- List: mark (solid dot, hollow ring, none), title, source, age; opened titles secondary. With a sentence: found rows, a hairline disclosure row "43 unsure" (open in searches, collapsed in pins), then "Check 1,200 older". Footer: "12 found, 9 unsure in the newest 300 of 6,200"; running, "212 of 300 checked"; failures, "31 not checked. Retry"; empty, "Nothing found in 300 items checked". Without a sentence, All Items puts this week's pin hits first (dot), rest chronological. No sources: "Add a source".
- Reader: a selection shows title, snippet, "Return to read"; none, blank. Opened: title; source, date, Open Original; "Text only. 4 images, 2 tables in the original."; status line; system serif, 66-character measure; 6 pt heat strip, 16 pt hit target.
- Find bar (Cmd-F; pushes text down; replaces the status line): "Find by meaning", "2 of 5", chevrons, Done.
- Add Source popover: one URL field over the live-filtered catalog; click or Return adds and checkmarks.
- Settings: key field with status (clearing removes the key), the disclosure, "About $0.04 today".

5. **Ranking rules**

Judged text: title and snippet (HN: title plus domain; arXiv: abstract's first 400 characters); never the source name.
Sentence: trimmed, whitespace collapsed, " becomes ', 200-character cap; any language, English frame.

- Default: `This item is about: "{q}"`.
- Ends in "?": `This item is about the subject of the question: "{q}"`.
- Whole-word exclusions, amounts, date words: capped at unsure, noting "Beam can't judge exclusions, amounts or dates. Describe only the topic."

Scheduling: on Return only; a new Return cancels the queue. A sentence searches every source and selects All Items; a source click filters locally. Cache first, then the newest 300 round-robin across sources; "Check 1,200 older" extends likewise. One global limiter of 64: viewport, search, pins, pre-judge. Ten consecutive failures stop the run.
Order: band, probability rounded to 0.05, date (pins: band, date). One unanimated snapshot every 200 ms; once the list has focus, arrivals append to their band and scroll anchors to the selection.
Bands: found; unsure; below, counted, not listed (Esc shows everything). Risk 1's eval sets thresholds per frame; 0.75 and 0.25 until then. Pending, failed, or judged on older text is "not checked", never "nothing".
Pins: refresh at launch, wake, every 30 minutes, Cmd-R; each new or edited item goes once, each pin a named question (per pin if MUST 8 fails); warning glyph while items stay unchecked after retries.
Cost: silent $0.50 daily breaker, $0.05 reserved for the reader; then "Daily limit reached. Resets at midnight."

6. **Reader rules**

Open: Return, Space or double-click; arrowing fetches and sends nothing.
Text: GitHub: feed text. arXiv: arxiv.org/html/{id}, else the abstract. YouTube: no reader; Return opens the browser. Others: feed content if 1,200+ characters; else the page (ephemeral session, Safari User-Agent, raw bytes into libxml2 `htmlReadMemory`), keeping article/main by XPath, else the block richest in paragraph text. Links, emphasis, code survive; images, tables only counted.
Passages: paragraphs, quotes, list items; under 40 characters merges forward, over 1,200 splits at a sentence end; headings and code shown, not judged. One per request, viewport first; cap 400. Frames: `This passage is about, or directly relevant to: "{q}"`; `This passage helps answer the question: "{q}"`.
Failed (thin text, HTTP error, paywall, JavaScript-only): title, snippet, "Beam couldn't get the article text. Open Original."
Carried sentence: opening from a search or pin judges passages at once; if Ben allows it, the top three found rows are judged ahead, 40 passages each.
Find: Return re-lights this article only; Esc restores the carried sentence.
Marks, one yellow: found, soft tint plus solid margin bar; unsure, hollow bar. Strip: solid tick, hollow tick, dimmed where unchecked. Cmd-G walks hits in order, wrapping.
Wording: "3 found, 2 unsure in 84 paragraphs checked"; "Nothing found in 84 paragraphs checked" (after "Matched by title." on a found row); "61 of 84 checked. Retry"; "Code not checked" where present. Never "no matches".

7. **V1 MUST**

Each is a `beam-eval` subcommand; Swift 5 language mode.

1. Cold start: wiped, keyless: 20+ items in 5 s, one opens readable, zero TypeSafe requests.
2. Sources: a blog homepage, a /channel/UC… URL and a GitHub repo resolve (host rules; feed body; `<link rel=alternate>`; common paths). Dirty fixtures (`&nbsp;`, BOMs, encodings, six date formats, YouTube's `media:` namespace) parse; dedupe GUID, then link. arXiv: export API, 100 results, one request per 3 s. Reddit: best-effort with a descriptive User-Agent and Retry-After; catalogued only if it passes.
3. Search, 300 items: first found row under 1.5 s, settled under 3 s; repeated offline: same list, zero requests.
4. Pins: 20 fixture items: exactly 20 requests whatever the pin count; one edited title: one more.
5. Reader: pre-judged results open lit within 300 ms, others within 2 s. GitHub Terms fixture, "which jurisdiction's law governs disputes": one paragraph lit; Cmd-G reaches it. Arrowing 20 rows: zero requests.
6. Honesty: a flag fails 30% of requests: exactly those dim or read "not checked"; "Nothing found" never appears.
7. Extraction: 40 saved pages: 32+ keep 90% of reference paragraphs; paywalls show the fallback; miss rate published.
8. Framing and ceiling: risk 1's eval passes; multi-question answers equal solo answers; a $0.01 ceiling stops requests.
9. Native: under 250 MB with 50,000 items; one TextKit 1 NSTextView reader; iconutil icon, About panel, no New Window or tab items, minimum window size, sidebar auto-collapse, dark-mode yellow; bundle re-signed after assembly; dev builds read `BEAM_KEY`.

8. **V1 CUT**

- Local files, PDF, pasted URLs: v1.1 by decree.
- Today digest, read/unread: All Items with pin hits first is the morning.
- Web view fallback, YouTube @handles: 200 MB per process; EU consent redirects.
- "Show others" row, meta-description re-judging, per-source "never send": Esc shows everything; no fetching unopened pages; v1 feeds are public.
- Keyword find, exclusion and date queries, "why it matched", percentages: the model is literal and cannot explain.
- Images, tables, comments, notifications, Dock badge, background agent, folders, tags, OPML, sync, tabs, Remove Key button: Open Original exists; pins already organise.

9. **Trust, privacy, cost**

Disclosure: "To judge meaning, Beam sends your sentences, your sources' titles and snippets, and paragraphs of articles you open or that rank in the top three, to TypeSafe with your key." TypeSafe's retention policy is linked; a veto removes the top-three clause.
Offline: fetched items stay readable; cached sentences repaint; a new search says "Offline. Showing what was already checked." A 401 shows "TypeSafe rejected this key".
NEVER: summarise, rewrite, answer or chat; show a probability; claim "nothing" beyond what was checked; send anything before key and disclosure; glass over reading text; cards, uppercase labels, sparkles, shimmer, gradients, meters, spinners.

10. **Keyboard map**

Cmd-L search; Return run or open; Down field to list; Esc close find bar, then clear sentence; Cmd-D pin/unpin; Cmd-0 All Items; Cmd-1…9 pins; Space open, then page; Cmd-F Find…; Cmd-G, Shift-Cmd-G next, previous hit; Cmd-O Open Original; Cmd-R refresh; Cmd-N add source; Cmd-Delete remove pin or source (sources confirm); Cmd-plus, Cmd-minus text size. All are menu items.

11. **Top risks**

Each runs before any UI.

1. The phrasing lottery silently empties a pin. Ben labels 10 sentences x 50 items y/n, about 20 minutes (fragments, questions, French, "MLX"), plus six exclusion, amount and date queries and false triggers ("sans-serif"). Candidates: the frame above; a second "useful to someone interested in" question capped at unsure; the measured reader-profile wording. The eval sets thresholds per frame; ship at found precision 0.9, found-plus-unsure recall 0.85.
2. Extraction is junk on a third of sites. The extractor over MUST 7's pages plus today's 60 HN links, read by eye; under 70% clean, Ben decides before UI work.
3. Bands land wrong: bare HN titles starve found; on-topic articles light everywhere. A CLI prints the found list for five of Ben's sentences (target 5 to 25 rows) and the lit share of 15 articles (over 40%: tighten the passage frame).

PART 2: Decisions log

Slop
S1 Accept: six lines plus mock.
S2 Accept: "Find by meaning".
S3 Accept: read/unread cut.
S4 Accept: launch restores selection.
S5 Accept: popover, checkmarks.
S6 Accept: all copy.
S7 Accept: silent breaker; Remove Key cut.
S8 Accept: three strip states.
S9 Accept: one header note.
S10 Accept: glyph inside field.
S11 Accept: sentences search everything.
S12 Accept: selection anchors scroll.
S13 Accept: all five states.
S14 Accept: all, in MUST 9.
S15 Part: Simon out, but cs.LG too (D6).

Feasibility
F1 Accept: beam-eval, Swift 5 mode.
F2 Accept: libxml2, ephemeral session.
F3 Accept: web view cut.
F4 Accept: discovery order.
F5 Accept: Reddit best-effort, off MUST.
F6 Accept: /channel URLs only.
F7 Part: export API yes; cap no: round-robin covers.
F8 Accept: Algolia adapter.
F9 Accept: fixtures in MUST 2.
F10 Accept: one TextKit 1 NSTextView.
F11 Accept: 200 ms snapshots.
F12 Accept: re-sign, BEAM_KEY.
F13 Accept: global limiter; pre-judge 40.
F14 Accept: iconutil.

Trust
T1 Accept: "?" only; subject frame.
T2 Part: one "about" frame, simpler; two-question variant goes to eval.
T3 Accept: detection, unsure cap, note.
T4 Accept: cleaning; source name dropped.
T5 Part: "Matched by title" yes; others row, footer no: Esc shows everything.
T6 Accept: Ben labels; eval sets thresholds.
T7 Accept: edits re-queue; stale is unchecked.
T8 Accept: coverage wording; glyph after retries.
T9 Part: disclosure, link, constant string yes; per-source opt-out no: feeds are public.
T10 Accept: 300 first, reserve, cancel, failure stop.

Daily
D1 Part: pin-hits-first yes; launch landing no: S4 wins.
D2 Accept: as S3.
D3 Part: collapsed unsure yes; meta refetch no: fetches unopened pages.
D4 Accept: Return or Space opens.
D5 Accept: a year kept; "Check older".
D6 Accept: round-robin; cs.LG out.
D7 Accept: arXiv HTML; YouTube opens browser.
D8 Accept: catalogued only if fetch passes.

Note: the Figma connector needs authorising in claude.ai connector settings, so the mock is a plain image until then. No code was written, no files were created and nothing was built.