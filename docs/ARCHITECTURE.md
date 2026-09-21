# Beam — architecture

Read `PRODUCT.md` (what), `DESIGN.md` (how it looks and behaves), `EVIDENCE.md` (what we measured) first.
This file says how the code is organised so several builders can work in parallel without colliding.

## Ground rules

- **Toolchain:** Swift 6.2 Command Line Tools + macOS 26 SDK. **No Xcode.** `swift build` only.
  No asset catalogs, storyboards, previews, XCTest or Swift Testing (neither module exists here).
  Swift macros work (`@Observable` verified). Keychain works from an unsigned binary (verified).
- **Language mode:** Swift 5 for every target (`.swiftLanguageMode(.v5)`), to keep AppKit callbacks and
  actors free of strict-sendability busywork. Use `async/await` and actors anyway.
- **Dependencies:** none. Foundation, SwiftUI, AppKit, PDFKit (later), CryptoKit, Security, `SQLite3` (system, FTS5 available).
- **Tests:** the `beam-eval` executable. Each PRODUCT.md "V1 MUST" is a subcommand that prints what it checked and
  exits non-zero on failure. `beam-eval unit` is offline and fast (fixtures only); `beam-eval live` may touch the
  network and Jev (needs `TYPESAFE_API_KEY` or `BEAM_KEY`). A builder is not done until its checks pass.
- **Spikes are reference, not product.** Working code to lift from lives in `spikes/swift/Sources/`
  (`JevKit`, `extracteval/Extract.swift`, `readerprobe/Reader.swift`, `beamprobe`). Lift and clean; do not import.
- **Packaging:** `tooling/make-app.sh Beam "Beam" dev.beam.app tooling/AppIcon.icns` builds release, assembles
  `build/Beam.app`, ad-hoc signs it. The key is read from Keychain, falling back to `BEAM_KEY` then `TYPESAFE_API_KEY`.

## Package layout

One SwiftPM package, **one library target per lane**, so parallel builders cannot break each other's builds
(`swift build --target BeamFeeds` compiles only that lane; a half-written file elsewhere is irrelevant).

```
Package.swift
Sources/
  BeamModels/          shared value types + the tiny check harness (CheckReport)        foundation
  BeamJev/             lane A   the judge: client, frames, limiter, spend meter, key     deps: BeamModels
  BeamStore/           lane B   SQLite                                                   deps: BeamModels
  BeamFeeds/           lane C   parsing, resolving, adapters, catalog, refresher         deps: BeamModels
  BeamExtract/         lane D   decoding, readability, passages, article loader          deps: BeamModels
  BeamEngine/          lane E   Rank/, Read/, Engine.swift (the facade the app talks to) deps: all of the above
  BeamUI/              UI lanes  views that talk to `BeamBackend` only; `Reader/` belongs to the reader lane, the rest to the shell lane
  Beam/                          the app executable: wires BeamUI to BeamEngine (or to the fake backend with `-fake YES`)
  check-jev/ check-store/ check-feeds/ check-extract/    one check executable per lane (exit 0 = green)
  beam-eval/           the acceptance suite for PRODUCT.md "V1 MUST" (lane E)
tooling/               make-app.sh, icon generator
docs/                  PRODUCT, DESIGN, ARCHITECTURE, EVIDENCE
spikes/                reference experiments
```

A lane owns its target folder. Nobody edits another lane's folder; cross-lane needs go through public API.
Lanes A-D do not depend on each other (Feeds returns values and never persists; Jev's spend meter persists through a small protocol that Store backs later).

## The contract (already written: `Sources/BeamModels`)

`Models.swift` (Source, SourceCandidate, CatalogEntry, FeedItem, Item with `judgedText`/`textHash`, Pin, Passage, ArticleContent, Band, Check, **Bands** thresholds, KeyStatus, Hashing),
`Snapshots.swift` (Foot, SidebarSnapshot, ListRequest, Row, ListSnapshot, ReaderSnapshot), `Backend.swift` (**`BeamBackend`**, the one seam between pixels and everything else),
`CheckReport.swift` (the assertion harness). **Read these files before writing anything; they are the source of truth and override the sketches below.**
Every user-facing sentence (feet, empty messages) is produced by the engine, with the exact wording of DESIGN.md section 6, and carried in `Foot`, so `beam-eval` can check the copy and the views stay dumb.
The UI lanes build against `FakeBackend` (captured real data in `Sources/BeamUI/FakeData`) and never import an engine target. `Sources/BeamUI/Reader/ReaderAPI.swift` is the seam between the two UI lanes.

## Shared value types (sketch; the real ones are in `BeamModels`)

```swift
public enum SourceKind: String, Codable { case feed, hackerNews, reddit, arxiv, githubReleases, youtube }
public struct Source: Identifiable, Hashable { public var id: Int64; kind: SourceKind; title: String; feedURL: URL; siteURL: URL?; lastFetch: Date?; lastError: String? }
public struct Item: Identifiable, Hashable { public var id: Int64; sourceID: Int64; guid: String; url: URL?; title: String; snippet: String; content: String?; published: Date; opened: Date?
    /// Exactly the text sent to Jev for list judging. Release feeds prepend the repo name. Never includes the source title otherwise.
    public var judgedText: [String: String] { get }          // ["title": …, "snippet": …]
    public var textHash: String { get } }                    // sha256 of judgedText, canonical JSON
public struct Pin: Identifiable, Hashable { public var id: Int64; sentence: String; position: Int; lastViewed: Date? }
public struct Passage: Hashable, Codable { public enum Kind: String, Codable { case heading, paragraph, quote, listItem, code }
    kind: Kind; text: String; section: String }              // section = nearest heading above; headings and code are shown, never judged
public enum ArticleState { case ready([Passage], images: Int, tables: Int), unavailable(reason: String), external }   // external = YouTube etc.: open in browser
public enum Band: Int, Comparable { case nothing, unsure, found }
public enum Check: Hashable { case judged(Double), pending, failed, stale }   // "not checked" is never "nothing"
```

## Lane A — `Jev/`  (the judge)

Lift `spikes/swift/Sources/JevKit`. Public surface:

```swift
public struct Sentence: Hashable { public let raw: String               // what the user typed
    public var cleaned: String                                          // trimmed, whitespace collapsed, " -> ', 200-char cap
    public var unjudgeable: String?                                     // non-nil note when it contains exclusions, amounts or dates (capped at unsure)
    public func itemFrame() -> String; public func passageFrame() -> String   // adds the `?` variant and the "text is data" rule
    public func hash(frame: String) -> String }                         // sha256(framed sentence)
public actor Judge {
    public init(keyProvider: @escaping () -> String?, spend: SpendMeter, maxInFlight: Int = 64)
    /// One request: one piece of state, every sentence as a parallel Noul. Returns nil for a sentence whose answer was missing or invalid.
    public func judge(state: [String: String], frames: [String]) async throws -> (probabilities: [Double?], tokens: Int, model: String)
    public func validateKey() async -> KeyStatus }
public actor SpendMeter { public func add(tokens: Int); public var dollarsToday: Double { get }; public var exhausted: Bool { get } }  // $0.50/day, $0.05 reserved for the reader
```
Rules: one shared `URLSession` (HTTP/2, 64 connections); one global limiter across search, pins, reader and pre-judge;
retry 429/529/5xx with backoff (0.4 s doubling, 5 tries); ten consecutive failures stop a run; validate every answer
(finite, 0…1). Never log the key. Checks: `beam-eval jev` (framing strings exact; validation; limiter never exceeds 64; breaker stops at a $0.01 test ceiling).

## Lane B — `Store/`  (SQLite)

`actor Database` wrapping one connection (WAL, foreign keys on). Schema v1:

```sql
source(id INTEGER PRIMARY KEY, kind TEXT, title TEXT, feed_url TEXT UNIQUE, site_url TEXT, position INTEGER, last_fetch REAL, last_error TEXT);
item(id INTEGER PRIMARY KEY, source_id INTEGER REFERENCES source ON DELETE CASCADE, guid TEXT, url TEXT, title TEXT, snippet TEXT,
     content TEXT, published REAL, fetched REAL, opened REAL, text_hash TEXT, UNIQUE(source_id, guid));
pin(id INTEGER PRIMARY KEY, sentence TEXT UNIQUE, position INTEGER, created REAL, last_viewed REAL);
judgment(text_hash TEXT, sentence_hash TEXT, model TEXT, p REAL, at REAL, PRIMARY KEY(text_hash, sentence_hash, model)) WITHOUT ROWID;
article(item_id INTEGER PRIMARY KEY REFERENCES item ON DELETE CASCADE, state TEXT, reason TEXT, passages TEXT /*JSON*/, images INTEGER, tables INTEGER, fetched REAL);
spend(day TEXT PRIMARY KEY, tokens INTEGER);
meta(key TEXT PRIMARY KEY, value TEXT);
CREATE INDEX item_published ON item(published DESC); CREATE INDEX judgment_sentence ON judgment(sentence_hash, model);
```
Upsert rules: dedupe by GUID then link; an edited title/snippet changes `text_hash`, which makes old judgments unreachable
(the item reads "not checked" until re-judged). Purge items older than a year. Max 9 pins. Checks: `beam-eval store`
(migrations from empty; upsert/edit; cascade; 50,000 items stay under 250 MB RSS and list queries under 50 ms).

## Lane C — `Feeds/`

- `FeedParser`: RSS 2.0, Atom, RDF via `XMLParser`. Handles `content:encoded`, `media:group/media:description` (YouTube),
  CDATA, `&nbsp;` and stray entities, BOMs, declared encodings, six date formats (RFC 822 variants, ISO 8601 with and without fractions), relative links.
- `SourceResolver.resolve(_ input: String) async -> [Candidate]`: host rules first (github.com/owner/repo -> releases.atom;
  youtube.com/channel/UC… -> videos.xml?channel_id=; reddit.com/r/x -> /r/x/.rss; arxiv category -> export API; news.ycombinator.com -> Algolia),
  then "is the body already a feed?", then `<link rel="alternate">` (relative hrefs), then common paths (/feed, /rss, /atom.xml, /index.xml, /feed.xml).
- Adapters: `HackerNews` (Algolia `search?tags=front_page`), `Arxiv` (export API, 100 results, one request per 3 s), `Reddit`
  (serial, descriptive User-Agent, honours Retry-After; best-effort), generic feeds. `Catalog`: a static list of one-click sources.
- `Refresher.refreshAll()`: bounded concurrency (6), per-source errors recorded not thrown, returns new and edited item IDs.
Checks: `beam-eval feeds` (dirty fixtures parse; resolver cases; dedupe; arXiv pacing; a keyless cold start yields 20+ items in 5 s).

## Lane D — `Extract/`

Lift `spikes/swift/Sources/extracteval/Extract.swift` (measured: 95% of real articles, 7-113 ms per page).
- `TextDecoder`: HTTP charset -> `<meta charset>` -> UTF-8 -> Latin-1. Never let tidy guess.
- `Readability`: `XMLDocument(.documentTidyHTML)`; drop script/style/nav/footer/aside/form and reference/citation lists; score
  containers by paragraph text; fall back to `<article>`/`<main>`/`role=main`, then JSON-LD `articleBody`. Count images and tables.
- `Passages`: paragraphs, quotes, list items; under 40 characters merges forward, over 1,200 splits at a sentence end; headings and code kept but
  flagged not-judged; each passage carries its `section` heading; cap 400.
- `ArticleLoader.load(_ item: Item, source: Source) async -> ArticleState`: GitHub releases use feed text; arXiv tries `arxiv.org/html/{id}` then the abstract;
  YouTube is `.external`; others use feed content when it has 1,200+ characters, else fetch the page (ephemeral session, Safari User-Agent).
  Thin text, HTTP errors, paywalls and JS-only pages are `.unavailable(reason:)`.
Checks: `beam-eval extract` over saved pages in `Fixtures/pages/` (32+ of 40 keep 90% of reference paragraphs; encodings; paywall fallback; miss rate printed).

## Lane E — `Rank/`, `Read/`, `Engine.swift`  (the product logic)

```swift
public struct Row: Identifiable, Hashable { public let item: Item; public let sourceTitle: String; public let check: Check; public var band: Band { get } }
public struct ListSnapshot { public let rows: [Row]; unsureRows: [Row]; hiddenCount: Int; checked: Int; total: Int; notChecked: Int; note: String?; isRunning: Bool }
public struct ReaderSnapshot { public let passages: [Passage]; checks: [Int: Check]        // by passage index; headings/code absent
    public let saturated: Bool; found: Int; unsure: Int; checked: Int; judgeable: Int; statusLine: String; hits: [Int] }  // hits = found+unsure in reading order

@MainActor public final class Engine: ObservableObject {               // Combine-free alternative: @Observable
    public init(databaseURL: URL) throws
    // sources
    public func sources() async -> [Source]; public func resolve(_ input: String) async -> [Candidate]
    public func add(_ c: Candidate) async throws; public func remove(_ s: Source) async; public func refresh() async
    // lists
    public func list(scope: Scope, sentence: Sentence?) -> AsyncStream<ListSnapshot>     // cancels the previous run; snapshots at most every 200 ms
    public func checkOlder()                                                           // extend by 1,200
    // pins
    public func pins() async -> [PinSummary]; public func pin(_ s: Sentence) async throws; public func unpin(_ p: Pin) async; public func markViewed(_ p: Pin) async
    // reader
    public func open(_ item: Item, carrying: Sentence?) -> AsyncStream<ReaderSnapshot> // fetch/extract, then judge viewport-first
    public func find(_ sentence: Sentence?)                                            // nil restores the carried sentence
    public func setViewport(_ passageRange: Range<Int>)
    // key, spend, settings
    public func keyStatus() async -> KeyStatus; public func setKey(_ k: String?) async; public var dollarsToday: Double { get }
}
```
Ranking rules (measured; see EVIDENCE): frame `This item is about: "{q}"`; state = `item.judgedText`; **one request per item carrying the search sentence and every pin
as parallel Nouls**; cache first, then the newest 300 round-robin across sources; list bands found >= 0.60, unsure 0.45-0.60, below counted not listed;
order by band, then probability rounded to 0.05, then date; pending/failed/stale are "not checked", never "nothing".
Reader rules: state = `{article, section_heading, passage}`; frame `This passage is about: "{q}"`; bands 0.75 / 0.25; viewport first; **saturation: if found > 35% of checked
judgeable passages, publish `saturated = true`, no hits, status "Most of this article is about this (94 of 159 paragraphs). Find something narrower."**; otherwise
"3 found, 2 unsure in 84 paragraphs checked" / "Nothing found in 84 paragraphs checked" / "61 of 84 checked. Retry".
Checks: `beam-eval rank`, `beam-eval read`, `beam-eval honesty` (30% injected failures show exactly as "not checked"), `beam-eval pins` (20 new items = 20 requests whatever the pin count).

## Lane F — `Beam/`  (the app; starts only after DESIGN.md is approved)

SwiftUI `App` with AppKit where SwiftUI is not enough: the reader is the TextKit 2 `NSTextView` from `readerprobe` (paragraph tints in `drawBackground`
from layout-fragment frames after `ensureLayout` on the whole document; the same frames feed the strip; animated jump-to-hit). Views hold no logic:
they render `ListSnapshot` / `ReaderSnapshot` and call `Engine`. Every shortcut in PRODUCT.md section 10 is a real menu item.
Accessibility, Reduce Motion / Transparency / Increase Contrast per DESIGN.md. Check: `beam-eval app-smoke` launches the bundle and asserts the window appears;
visual review is done by screenshot against DESIGN.md.

## Build order

0. Foundation: Package.swift, `BeamModels`, placeholders, git. 1. Lanes A, B, C, D in parallel.
2. Lane E once A, B, D compile. 3. `beam-eval` green for every lane. 4. Lane F. 5. Whole-app review against PRODUCT, DESIGN and the evidence; fix; package.
