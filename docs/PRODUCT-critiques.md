# slop

1. **Wall of text and seven open questions.** Ben asked to be consulted, not to read eleven sections. Send him six lines plus one mock. State serif, text-only reader, hidden "nothing" rows and no digest as decisions he can veto. The real questions are starter sources and pre-judging unopened articles. Build nothing until he replies.
2. **"Ask" implies answers**, which contradicts "never answers". Call it Find, with placeholder "Find by meaning" and menu item Find….
3. **Read/unread is a second organising idea.** Cut readAt, the 2 s timer, semibold, Cmd-U, Shift-Cmd-K and "next unread". Pin count becomes found items that arrived since that pin was last viewed, and viewing clears it. Opened titles go to secondary colour.
4. **Launch picks a pin for you.** Restore the last selection and scroll position instead, like any Mac app.
5. **The Add Source sheet is a form, with 24 Add buttons plus Done.** Make it a popover from "+" with one field and the catalog filtering beneath. Click or Return adds, and added rows show a checkmark.
6. **Copy.** "Unsure, read these yourself" becomes "Unsure". The footer becomes "12 found, 9 unsure in 480 checked", matching the reader's grammar. While running it reads "212 of 480 checked", with no spinner and no bar. When the find bar is open, hide the reader status line, because "2 of 5" suffices.
7. **The $0.50 ceiling is 20,000 items a day.** Nobody reaches it, so make it a silent circuit breaker with one error string, not a question for Ben. Cut Remove Key, since clearing the field removes it.
8. **The heat strip has four states including hatching in 6 pt, which is mush.** Use a solid tick, a hollow tick, and dimmed unchecked stretches. Draw it at 6 pt with a 16 pt hit target.
9. **Inline "Not shown" lines** litter figure-heavy ML posts and read as breakage. Put nothing inline and add one header note: "Text only. 4 images in the original."
10. **A pin button that appears and vanishes shifts the toolbar.** Put a pin glyph inside the search field's trailing edge, filled when pinned. At nine pins it is disabled, with tooltip "Nine pins maximum".
11. **Search scope is undefined.** Decide that a sentence always searches everything and selects All Items. Clicking a source afterwards filters locally with zero requests.
12. **Streaming contradiction.** Rows inserted above still push the selected row down. Anchor scroll to the selection.
13. **Missing states.**
    - No selection: blank reader, no illustration.
    - Zero results: "Nothing found in 480 items checked".
    - No pins: hide the Pins header.
    - No sources: "Add a source" in the list.
    - Failing source: error as the row tooltip, Retry in the context menu.
14. **Missing finish.**
    - A hand-made .icns via iconutil, otherwise the app gets a generic icon.
    - An About panel.
    - Remove SwiftUI's default New Window and tab menu items.
    - A minimum window size, with sidebar auto-collapse on the 13-inch Air.
    - The yellow specified for dark mode too.
15. **simonwillison.net is the generic AI-crowd default.** Use HN, arXiv cs.LG and MLX GitHub releases instead, which exercise three source kinds and match Ben's interests.

# feasibility

1. Tests: the Command Line Tools on this machine ship Testing.framework but no XCTest (I checked). Make each MUST a `beam-eval` CLI subcommand. Set Swift 5 language mode, or the agents lose a day to Sendable errors.
2. Extraction: XMLDocument's tidy predates HTML5 and drops `<article>`/`<main>`, so the spec's first rule silently fails. Use the system libxml2 `htmlReadMemory` plus XPath (its modulemap is in the SDK here, checked), and feed it raw bytes so it handles charset. Send a Safari User-Agent. Use an ephemeral session rather than no cookies, which causes redirect loops.
3. JS pages and paywalls: cut the WKWebView fallback, which costs about 200 MB per WebContent process on 8 GB. Show only the fallback line, and publish the miss rate from risk 2's CLI.
4. Discovery, in this order: host rules, then a body that is already a feed, then `<link rel=alternate>` resolved against the final URL, then probing /feed, /rss, /atom.xml and /index.xml.
5. Reddit: `.rss` answers 429/403 to default user agents and increasingly to anonymous clients. Use a descriptive UA, one request per host, conditional GET, and honour Retry-After. Drop it from MUST 2 and treat it as best-effort with the warning glyph.
6. YouTube: feeds need a `channel_id`, and @handle pages redirect EU IPs to consent.youtube.com. v1 should accept only /channel/UC... URLs and catalog entries. Feeds carry 15 entries, and `media:description` needs namespace-aware parsing.
7. arXiv: the RSS feed is daily, empty on weekends, and runs 150-400 items a day, so cs.LG alone eats the 1,500 cap. Use the export API's Atom output (`max_results=100`, one request per 3 s) plus a 200-item per-source cap.
8. HN: the official RSS has 30 items and no text, so "one parser" breaks. Add a 50-line Algolia JSON adapter; don't depend on hnrss.org.
9. Feed parsing: XMLParser dies on `&nbsp;`, BOMs and bad encodings, and dates come in six formats. Sanitise, retry via XMLDocument tidy-XML, run a POSIX DateFormatter cascade, and dedupe on guid then link. Budget half a day.
10. Reader: Text-per-paragraph loses cross-paragraph selection, exact scroll-to and strip geometry. Use one read-only NSTextView forced to TextKit 1:
    - temporary background attributes for tints, so no relayout;
    - margin bars drawn from `boundingRect`;
    - `scrollRangeToVisible` for jumps;
    - strip ticks from the same rects.
    Space paging comes free.
11. Streaming list: per-result List mutation janks and drops selection. Buffer in an actor and publish one sorted snapshot every 200 ms, with no animation and stable ids. Once the list has focus, arrivals append to their band's end.
12. Keychain: the data-protection keychain needs a team entitlement (-34018). The login keychain works ad-hoc, but its ACL binds to the cdhash, so every rebuild prompts. Re-sign the bundle after assembly, and have dev builds read a `BEAM_KEY` env var.
13. Concurrency: search, reader and pins at 64 each exceed HTTP/2's roughly 100 streams. Use one global limiter of 64 with priority viewport > search > pins > pre-judge. Use a sliding-window TaskGroup and cancel on a new Return. Cap pre-judging at 40 passages per article, not 400.
14. Icon: plain .icns via iconutil (no Icon Composer).

Nothing was built or changed; I ran two read-only SDK checks. The Figma connector needs authorising in claude.ai connector settings and is unavailable until then.

# trust

1. Question routing misfires. "Comment systems for static blogs" opens with an interrogative, and "c'est quoi MLX" doesn't. Fix: use the question frame only when the sentence ends in "?". For items, "helps answer" can't be judged from a title, so use `This item is about the subject of the question: "{q}"`. Keep "helps answer" for passages.

2. The default frame is a disjunction. "Useful to someone interested in" passes everything on broad queries like "AI". Fix: ask two named questions, `about` and `useful`. Found needs `about` >= 0.75. A match on `useful` alone caps at unsure. Also eval the measured reader-profile wording.

3. Negations, amounts and dates fail silently. "AI but not LLMs" lights LLM posts; "under 3B parameters" and "this week" can't be judged. Fix: detect these locally (not/sans/sauf; digits with comparatives; latest/cette semaine). Cap those results at unsure. Show "Beam can't judge exclusions, amounts or dates. Describe only the topic." Eval six such queries.

4. The judged input is dirty. Quotes or newlines in {q} break the frame, and the source name makes "security news" light every Hacker News item. Fix: swap " for ', collapse whitespace, cap at 200 characters, and drop the source name from the judged text.

5. Title-only judging plus hidden rows buries good articles. Fix: add a last row "Show 459 others", and a footer line "212 had a title only". A found row that opens with nothing lit reads "Matched by title. Nothing found in 84 paragraphs checked."

6. The thresholds are borrowed. 0.25/0.75 was validated on plain propositions, not on relevance frames. Fix: the eval sets thresholds per frame (item, passage). Labels are pairs: 10 sentences x 50 items, labelled by Ben rather than an LLM, French included.

7. Edited items go stale. "Each new item goes once" never re-judges an HN title a moderator has edited. Fix: item identity is the GUID, else the URL. A changed text hash re-queues the item for every pin. A band shows only if its judgment matches the current text; otherwise the row is "not checked". If multi-question answers don't equal solo answers, send one request per item per pin.

8. Counts overstate coverage. Fix: say "Checked the newest 1,500 of 2,300". Pins show the warning glyph while any item is unchecked. The reader line adds "9 code blocks, 2 tables not checked".

9. "Nothing else" is false. The key, the IP address and the Cmd-F sentences go too, and pre-judging fetches pages the user never opened. Fix: "Beam sends your sentences, your sources' titles and snippets, and paragraphs of articles you open or that rank in the top three, to TypeSafe with your key." Link TypeSafe's retention policy. Validate the key with a constant string. Add a per-source "Never send to TypeSafe".

10. The ceiling punishes rephrasing, which the phrasing lottery forces. About 13 fresh 1,500-item sentences cost $0.50, and then Beam is dead until midnight. Fix: judge the newest 300 first, then offer a "Check 1,200 older" row. Reserve $0.05 for the reader. Drop queued requests on a new Return, and stop after 10 consecutive failures.

All of this is for Ben's yes or no; nothing here gets built first.

# daily

I would open it daily for a week, then about twice a week. Issues below follow a Monday morning and a Thursday evening walk-through. The fixes sharpen what is specified and add no features.

**Monday 8:40, coffee, ten minutes**

1. **Four pins mean four visits.** I go through Cmd-1 to Cmd-4 and see the same MLX post in two pins. All Items does not help, because arXiv cs.LG alone is 150+ papers a day.
   - Fix: keep the same screens. All Items sorts "found by any pin" first, marked with a dot, and the rest chronologically below.
   - Every new item is already judged against every pin, so this costs zero extra requests.
   - Launch lands on this list, which becomes the whole morning routine.

2. **Unread counts never reach zero.** I skim 25 found rows and open 4. The other 21 stay unread, the counts grow all week, and I quit out of guilt.
   - Fix: the count means "new since you last opened this pin" and clears when I view the pin.

3. **Unsure will be 40 to 60 rows on bare HN titles, not 9.** That is a second inbox I never finish.
   - Fix: in pins, collapse unsure to one row such as "43 unsure" that expands on click. Show it open by default only for typed searches.
   - For unsure HN rows, fetch the linked page's meta description and re-judge once before listing them.

4. **Selection behaviour is unspecified.** If arrowing through the list loads articles, every row I pass fetches a page, sends up to 400 paragraphs to TypeSafe and is marked read after 2 s.
   - Fix: selecting a row shows title and snippet only. Return or Space fetches the article and lights it.
   - An item counts as read only when opened that way.

**Thursday 22:30, "that 4-bit quantization post from a few weeks ago"**

5. **The 14-day window plus the 30-day purge kills my evening search.** At night I search to recall something that already passed through my feeds. Items are about 500 bytes, so purging saves nothing.
   - Fix: keep a year of items. Search newest-first to 1,500, then show a footer: "Checked 1,500 of 6,200. Check older".
   - Each "Check older" click costs about $0.04.

6. **The 1,500 cap is newest-first globally.** arXiv uses it up, so blog, subreddit and release items more than a few days old are never checked.
   - Fix: fill the cap round-robin per source.
   - Replace the cs.LG starter with a narrower feed.

7. **The lit paragraphs are missing on my main sources.** They are the one thing no other reader does, but arXiv shows a single abstract paragraph and YouTube shows a description.
   - Fix: arXiv fetches arxiv.org/html/{id} when it exists and runs the normal extractor. Otherwise it shows the abstract.
   - YouTube and other stub items skip the reader, and Return opens the browser.

8. **Reddit RSS often returns 429 to default URLSession user agents.**
   - Fix: send a custom User-Agent with backoff, and prove it in MUST 2 before the catalog offers subreddits.

**Month-two deciders:** 1, 2 and 7.

**Ben's veto list:**
- Bless: text-only reader, hidden "nothing" rows, and top-three pre-judging.
- Veto: cs.LG as a starter source.
- "No Today digest" only holds if fix 1 lands.

Nothing here is built. All of it waits for Ben's yes or no.

