# Judges

[
 {
  "scores": [
   {
    "direction": "hig",
    "taste": 8,
    "nativeFeel": 9,
    "clarity": 7,
    "feasibility": 9,
    "notes": "Closest to 'Apple made it'. Strengths: a stock three-column split and the system search field. Mail-style title and subtitle carry all list status, so no chrome is added. The NSScrollView find-bar slot is a real AppKit API; it fixes the title overlap and matches every Mac user's Cmd-F habit. There are only three custom marks in one hue. hitInk blended toward the label colour is the only bar colour among the three that survives light mode. Weak spots: (1) The main input is a stock trailing .searchable field. Its own wireframes truncate both the sentence and the placeholder ('Describe what you wa…'), and that placeholder is the only instruction in an app with no onboarding. (2) A second Return re-runs the search instead of opening the top row, so PRODUCT.md's Return-Return aha is missing. (3) The 6 pt gutter dot reads as Mail's unread dot. Listed rows (p >= 0.45) map to 0.75-1.0 opacity, which is imperceptible, so 'zero found, a dozen unsure' looks like a dozen found. (4) Pins are rank-ordered, although PRODUCT.md orders pins by date. (5) An unsure current hit gets a tint, which breaks 'tint = found'. (6) No article-fetching state is specified. (7) Like the other two, it omits the binding saturation state. Feasibility caveats: navigationSubtitle is a plain string, so no numericText transition; selection-anchored insertion needs an NSTableView-backed list, not SwiftUI List (true of all three directions)."
   },
   {
    "direction": "editorial",
    "taste": 7.5,
    "nativeFeel": 7,
    "clarity": 8,
    "feasibility": 7.5,
    "notes": "It has the best organising idea of the three: authors speak in New York on paper, and Beam speaks in small SF at the edges. One solid / open / hairline / none grammar runs through margin, strip and gutter. Worth keeping: the wide principal field shows the whole sentence and placeholder; ink links keep the page quiet; bar-thickening marks the current hit without touching the tint grammar; pins by date with a closed 'less likely' fold follows the spec; the smoothstep gutter mark visibly separates 0.45 from 0.60. The character is paid for with non-stock parts. Serif list titles on a paper list column read as 'designed', not Apple, and Ben asked for the system font. Two 28 pt feet are permanent chrome. The ask field at the bottom-left foot is clever because nothing moves, but no Mac user looks for Find there. Numbered-circle pin icons, a recents menu and a 700 ms tint swell are more than needed. The 1320 x 860 default window is nearly full-screen on his 13-inch Air. It lists everything >= 0.25, which EVIDENCE.md measures as 10% precise noise. The margin says dotted while the strip says hollow, so one state has two grammars. It has no saturation state."
   },
   {
    "direction": "instrument",
    "taste": 7,
    "nativeFeel": 6.5,
    "clarity": 7.5,
    "feasibility": 6.5,
    "notes": "It is the purest reading of 'one clear input'. The launch screen is the clearest of the three. Return-Return with a pre-selected top row is exactly the spec's aha. Putting the snippet in the row removes the odd preview half-state. The 980 x 720 window suits a MacBook Air. The purity is paid for with hidden modes and custom parts. Cmd-F silently rescopes the toolbar field; a glyph swap is the only cue, and a mouse user cannot tell which scope a click gives. 'Ask this article' is chat wording. The field is a custom NSTextField with no clear button posing as a search field, and its glass capsule in the toolbar is a rendering risk. Swapping the list for the reader behind a Back button drops the list during the core triage loop (Esc, Down, Return per article); that is the iPad/News pattern, not Mail/Reeder. The reader toolbar grows to four items, including a glass hit-counter group. Rows slide for 250 ms on every 200 ms snapshot, which means 1-3 s of continuous motion. Pure systemYellow bars and 1 pt hollow strokes on white are near-invisible in light mode. The 0.25 list floor is noise. The four-layer Esc ladder means a double Esc destroys the sentence. It has no saturation state."
   }
  ],
  "winner": "hig",
  "graft": [
   "From editorial and instrument: replace the stock trailing .searchable field with a wrapped NSSearchField as the toolbar's principal item, 320-560 pt wide. Keep hig's title and subtitle over the list column and its adjacent standard pin button. The full sentence and the full placeholder 'Describe what you want to read' must always be readable.",
   "From instrument: Return on an unchanged sentence opens the selected row. After the first paint the top row is selected, unemphasised while the field has focus. This delivers PRODUCT.md's Return-Return aha. It also fills the reader with the 'Return to read' preview instead of a blank pane, and still sends no requests.",
   "From editorial: replace the 6 pt dot with a gutter bar, 2.5 pt wide, title height, in hitInk. Opacity is 0.2 + 0.8 x smoothstep(0.25, 0.75, p). It rhymes with the reader's margin bar and cannot be mistaken for Mail's unread dot. A 0.45-0.60 row becomes visibly fainter than a >= 0.60 row, so 'zero found, a dozen unsure' looks honest.",
   "From editorial: pin lists show items above the likely threshold ordered by date, newest first, with the 'less likely' fold closed. Searches stay rank-ordered. New items land at the top, so the sidebar badge needs no 'New' label.",
   "From editorial: mark the current hit by thickening the margin bar and widening its strip mark to 10 pt. This works identically for found and unsure. Keep hig's one-step stronger tint for found paragraphs only. The widened strip mark also answers 'where am I' when the find bar is closed.",
   "From editorial and instrument: add system help tags on margin marks, 'Unsure. Read this yourself.' and 'Not checked'. They explain the hollow bar and the rail at no visual cost.",
   "From editorial: set body links in label ink with a 1 pt tertiary underline, not accent colour. A link-heavy article then never goes blue-on-yellow, or yellow-on-yellow when the user's accent is yellow or orange. 'Open Original' and 'Retry' stay accent.",
   "From instrument: dim the stale list. If nothing has arrived 150 ms after Return, the old list drops to 40% opacity until the first snapshot; cached results swap in with no dim. It is opacity only, so it fits hig's motion rules, and it acknowledges Return nearer the eye than the subtitle does.",
   "From editorial: the article opening sequence, which hig does not specify. Title and meta appear at once in their final position. The body fades in over 200 ms when extracted. 'Getting the article' shows only if extraction takes more than 1 s. The article never scrolls by itself.",
   "From instrument: hollow strip ticks get a 5 pt minimum height, so an unsure tick still reads as hollow and not as a thin solid.",
   "Copy from instrument and editorial: close the key-sheet disclosure with 'Nothing has been sent yet.' Add the Settings statuses 'Key works. Stored in your Keychain.' and 'No key. Beam works as a plain reader.' The disclosure gains the top-three clause only when the toggle is on.",
   "Missing from all three, and binding per the PRODUCT.md addendum: add the saturation state. When more than 35% of checked paragraphs are found, draw no tints, no bars and no strip marks. The rails retract as usual. The header status line reads 'Most of this article is about this (94 of 159 paragraphs). Find something narrower.' Cmd-F opens hig's find bar. No warning glyph or colour; it must read as a calm sentence, not an error."
  ],
  "kill": [
   "hig: the stock-width trailing .searchable field. It truncates the sentence and the only instruction in the app.",
   "hig: the 6 pt gutter dot with opacity clamp(p/0.6, 0.35, 1). It reads as Mail's unread dot and is effectively binary across the rows that are listed.",
   "hig: the half-alpha hitFill on an unsure current hit. Tint must mean found, nothing else.",
   "hig: a second Return in the field re-running the same sentence.",
   "hig: pinned lists shown rank-ordered. PRODUCT.md says pins order by date.",
   "hig: .contentTransition(.numericText()) on the navigation subtitle. It is a plain window string, so just swap the digits.",
   "editorial and instrument: the 0.25 list floor. EVIDENCE.md measures the 0.25-0.60 band at 10% precision. List from 0.45 and put the rest behind 'Show N less likely'.",
   "editorial: New York list-row titles and the paper list column. Keep the serif for the article only; the list stays a stock inset List in SF.",
   "editorial: the permanent 28 pt running feet under both columns, and the ask field morphing in at the bottom foot. Find belongs in the top find bar, where every Mac app puts it.",
   "editorial: the dotted margin rule for unsure. The margin would say dotted while the strip says hollow; keep one hollow grammar.",
   "editorial and instrument: numbered circles or numerals as pin icons. Apple never labels Cmd-digit targets; use the pin glyph and let the menu show the shortcut.",
   "editorial: the recents menu in the search field, the 700 ms tint swell on jump, and the 1320 x 860 default window.",
   "instrument: the modal single field, where Cmd-F rescopes the toolbar field. Also the 'Ask this article' wording, the missing clear button, and the custom NSTextField capsule.",
   "instrument: the list-to-reader swap with a Back button, and Esc as 'back' in a four-layer ladder. Keep hig's two-step Esc: find bar, then sentence.",
   "instrument: rows sliding 250 ms on every snapshot and the 6 pt settle on open. Keep hig's rule that motion is opacity only and nothing slides.",
   "instrument: pure systemYellow bars and 1 pt hollow strokes (near-invisible on white), the 2 pt grey thread, and the full-height grey strip line while checking.",
   "instrument: the toolbar hit-counter group, the 'New' / 'Earlier' group labels, three-element 60 pt rows with a trailing meta column, and the add-source sheet with a Done button. Keep the popover.",
   "All directions: shipping without the saturation state, and any design where 'zero found, a dozen unsure' looks the same as a confident result list."
  ]
 },
 {
  "scores": [
   {
    "direction": "hig",
    "taste": 7,
    "nativeFeel": 9,
    "clarity": 6.5,
    "feasibility": 9,
    "notes": "Most native and cheapest to build. It uses a stock three-column split view. It puts the in-article ask in the system find-bar slot (findBarView with .aboveContent), which fixes the title overlap. Sheet, popover and Settings are stock, motion is opacity only, and nothing slides. Its best ideas: the dot ceiling calibrated to the measured 0.60 threshold, the explicit 'Show 262 less likely' row, the correct macOS title-case rule, and the icon geometry with a 16/32 px variant.\n\nProblems:\n- It demotes the product's one input. `.searchable` gives a narrow trailing field whose width SwiftUI cannot set. The spec's own wireframes show the prompt and the sentence truncated ('Describe what you wa…'), so the only instruction in the app is cut off.\n- Status is spread over five places: window subtitle, notice row, tail rows, header status line and find-bar counter. None is visible mid-article. The hit counter and chevrons exist only while the find bar is open.\n- The leading gutter dot sits where Mail, Reeder and Podcasts put the unread dot. With opened titles going secondary, it will read as 'unread'.\n- The live status line sits inside the text storage, so every tick shifts character ranges under the selection and the tint mapping.\n- `.contentTransition(.numericText())` cannot apply to an NSWindow subtitle.\n- An unsure current hit gains a half-alpha yellow fill, which makes it look found.\n- The pinned view cannot show which rows are the '3 new'.\n- clamp(p/0.6, 0.35, 1) draws p=0.45 at 0.75 opacity, over-claiming a band that is one-in-three relevant.\n- Nine identical pin glyphs in the sidebar carry no information.\n- Rows are Mail-dense rather than airy.\n- The mandatory saturation state (more than 35% found) is missing."
   },
   {
    "direction": "editorial",
    "taste": 8.5,
    "nativeFeel": 7.5,
    "clarity": 8,
    "feasibility": 8,
    "notes": "Strongest idea. It is the only direction with a system for Beam's voice: authored text in New York on opaque paper, and everything Beam says in one running foot. Chrome stays stock, with no custom glass.\n\nStrengths:\n- Status and the '1 of 5' counter with chevrons are always visible, so hit-walking is discoverable without opening anything. Errors always appear in the same place.\n- The foot ask means nothing moves and the counter never jumps. It also suits the missing saturation line, because Cmd-F would turn that line into the ask field in place.\n- The wide principal NSSearchField (320-560 pt) keeps the prompt legible.\n- The gutter bar repeats the margin-bar grammar, so one article teaches the list.\n- Adjacent tints stay separate with a 4 pt gap.\n- The current hit is shown by a thicker bar and a wider strip mark. That is shape-based, survives Reduce Motion and greyscale, and works for unsure hits.\n- Numbered-circle pins double as Cmd-digit hints.\n- It shows platform awareness: a sheet for the key because a popover would close while fetching it, a scroll-edge fallback for the hosted NSScrollView, and 'the article never scrolls by itself'.\n- Pins ordered by date put new items on top.\n\nWeak spots, mostly cosmetic and removable:\n- New York list titles. HN titles and 'mlx v0.29.1' look wrong in serif, and it fights the system selection highlight.\n- Body-link hover colour.\n- A 700 ms tint swell.\n- An unconditional list dim on every Return.\n- Sentence-case commands ('All items', 'Add source', 'Not now'), which read as iOS or web on a Mac.\n- The window title is removed, so a collapsed sidebar loses context.\n- A 0.25 list floor, which EVIDENCE calls 10% precise.\n- A three-number foot sentence.\n- A 1320 x 860 default that does not fit Ben's 13-inch Air (1470 x 956 pt) with the Dock showing.\n\nA bottom-placed find is unconventional but defensible: AppKit itself offers findBarPosition .belowContent. The mandatory saturation state is missing."
   },
   {
    "direction": "instrument",
    "taste": 8,
    "nativeFeel": 6,
    "clarity": 7.5,
    "feasibility": 6.5,
    "notes": "Best first glance, and the closest fit to 'one clear input, lots of air'.\n\nStrengths:\n- It matches Beam's semantics. Opening is deliberate, so a push replaces the three-pane preview pane, which would show only 'Return to read'.\n- It keeps the full 680 pt measure on a 13-inch Air.\n- Return-Return delivers PRODUCT.md's aha literally.\n- The conditional dim at 150 ms, the '5 hits' label, 'Stored in your Keychain', and laying content below the toolbar are refined details.\n\nProblems:\n- Structurally it is a search-engine results page: field, results, Back. That is the web's pattern, not a Mac reader's. The ranked list disappears while reading, the next article costs Esc, Down, Return, and the preview PRODUCT.md specifies is gone. List marks and lit paragraphs are never on screen together.\n- The single field is a mode. The carried sentence vanishes from view when asking the article, and Return means run, open or re-light depending on invisible state.\n- The highlight stays on the first slot while rows slide beneath it. Selection must follow the item, not the slot; this is Spotlight's top-hit bait-and-switch.\n- 250 ms row slides on every 200 ms snapshot mean constant motion for 1 to 3 seconds.\n- Esc as Back, plus a four-rung Esc ladder, will lose articles on a double-tap. Esc cancels transient things on the Mac; Cmd-[ is Back.\n- The custom NSTextField subclass, with an in-field pin and no clear button, is the most hand-rolled control. It sits in the glass toolbar, where imitations are most visible, and it is the costliest piece to polish without Xcode's view debugger.\n- A 2 pt tertiary thread on every paragraph is heavy.\n- A code-block radius implies a box.\n- Context menus are in sentence case.\n- The mandatory saturation state is missing."
   }
  ],
  "winner": "editorial",
  "graft": [
   "[hig] Capitalisation rule: macOS title-style caps for sidebar items, buttons, links that act as commands, context menus and menu bar ('All Items', 'Add Source', 'Open Original', 'Not Now', 'Copy Feed URL'). Use sentence case only for things that read as sentences (foot status, disclosure, empty states).",
   "[hig] Stock list: `List(selection:)` in `.inset` style with SF Pro 13/16 medium titles and 11-12 pt secondary meta, system separators, system selection. Keep the paper background if wanted, but no serif in rows. The mark turns white on an emphasised selection. Under Increase Contrast all list marks go to full opacity.",
   "[hig] Mail-style toolbar arrangement: keep `navigationTitle` (the list name only, no subtitle, since the foot carries counts) over the list column so context survives a collapsed sidebar. Put the wide NSSearchField and the separate standard pin toolbar button over the reader section, rather than a centred principal item straddling the column divider.",
   "[hig] Explicit tail rows in searches as well as pins: 'Show 262 less likely' and 'Check 1,200 older', reachable with Down arrow and Return. Set the listing floor near 0.45 per the measured bands. Use HIG's two-number wording 'Newest 300 of 6,200 checked' in the foot.",
   "[hig] Find opens pre-filled with the carried sentence, with the text selected. The counter and chevrons are live immediately and typing replaces the text. This is the macOS find convention. Apply it to the foot ask.",
   "[hig] One-notice-at-a-time priority rule, applied to the foot: key rejected, then daily limit, then offline, then the exclusions note.",
   "[hig] Motion discipline: opacity only, nothing slides, no scale, glow or stagger. Judgments are final on arrival, so rows never reorder. After a jump, use a 150 ms tint step in place of the long swell.",
   "[hig] Strip engineering: inset the strip by the legacy scroller width so the overlay scroller never covers it. Make it invisible unless there are marks. A jump lands the hit's top at about 30% of the viewport.",
   "[hig] Evidence-calibrated mark ceiling: full opacity from p >= 0.60, because titles rarely score above 0.8 and 0.60 is 100% precise. Combine it with Instrument's offset ramp so the fade starts near 0.25-0.30 and not at 0. Then p=0.45 draws at about half strength, and a list of zero found and a dozen unsure looks tentative.",
   "[hig] App icon geometry: 1024 canvas with an 824 pt continuous-corner body, so Tahoe does not box it as a legacy icon. Add a 1 px inner edge at 8% black. Use a simplified 16/32 px variant: three bars, the middle one lit, no strip.",
   "[hig] Sidebar details: `.badge(n)` for new counts (it renders as plain secondary digits on macOS), and drag to reorder pins, with the order setting Cmd-1 to Cmd-9. Settings lines 'Beam stops at $0.50 a day.' and 'Clear the field to remove the key.'",
   "[instrument] Return-Return: once the first snapshot has painted, a Return in the field with unchanged text opens the top-ranked row. This is PRODUCT.md's literal aha ('Return again'). Bind it to the item that was top when the key went down, never to a slot.",
   "[instrument] Conditional search-start dim: dim the old list only if nothing has arrived by 150 ms. Cached results cross-fade in over 120 ms with no dim. This replaces Editorial's unconditional fade to 40%.",
   "[instrument] Hit counter label: '5 hits' before the first jump, then '2 of 5', in monospaced digits, hidden at zero hits. This replaces Editorial's bare chevrons.",
   "[instrument] In pin lists, mark where the '3 new' end: a quiet 'Earlier' divider (Notes-style sentence-case group label or one hairline) below the items that arrived since the pin was last viewed. Editorial's by-date order already puts them on top.",
   "[instrument] Lay the reading surface out below the toolbar by default, instead of extending it underneath and relying on the scroll-edge effect reaching a hosted NSScrollView. It is the simplest guarantee of no text under glass.",
   "[instrument] Tooltips on margin marks that teach the grammar in place: 'Unsure. Read this yourself.' and 'Not checked'. Trust lines: 'Key works. Stored in your Keychain.' and, in the key sheet, 'Nothing has been sent yet.'",
   "[instrument] Laptop-first sizing: derive the default window from the screen's visibleFrame, since Ben's 13-inch Air is 1470 x 956 pt and the Dock takes height. Auto-collapse the sidebar when an article opens in a narrow window, so the measure is not squeezed.",
   "[missing from all three, mandatory per the addendum] Add the saturation state. When more than 35% of checked paragraphs are found, draw no tints and no strip marks and hide the counter. The grey rules retract to nothing. The foot reads 'Most of this article is about this (94 of 159 paragraphs). Find something narrower.' Cmd-F turns that same line into the ask field. Decide only after a minimum number of paragraphs are checked, so yellow does not appear and then vanish. It must read as calm and intended, since it is the common case for broad searches."
  ],
  "kill": [
   "[editorial] New York for list-row titles. Tech titles, version strings and 'Show HN:' look wrong in serif. It fights the system selection highlight and scans more slowly than SF. Keep the serif for the reader and preview only.",
   "[editorial] Body links changing colour on hover. Hover effects are web behaviour, and NSTextView links do not hover. Use static link styling and the pointing-hand cursor only.",
   "[editorial] The 700 ms tint swell to 1.6x alpha on jump. The thicker bar and wider strip mark already carry the 'current' state; one short tint step is enough.",
   "[editorial] Fading the old list to 40% on every Return. It flickers on cached and sub-400 ms results.",
   "[editorial][instrument] Sentence-case commands and sidebar items ('All items', 'Add source', 'Open original', 'Not now', 'Copy feed link', 'Remove…'). They read as iOS or web on a Mac.",
   "[editorial] `.toolbar(removing: .title)`. With the sidebar auto-collapsed, nothing says which list or source filter is showing.",
   "[editorial] Recents menu in the search field. Pins are the history, and it is one more control that can be removed.",
   "[editorial] Listing everything down to p 0.25 in searches. EVIDENCE measures the 0.25-0.60 band at 10% precision, so fold the tail behind an explicit row. Also drop the three-number foot sentence '21 shown from the newest 300 of 6,200'.",
   "[editorial] The fixed 1320 x 860 default window. It is taller than the usable height on a 13-inch Air with the Dock visible.",
   "[hig] `.searchable` with default toolbar placement as the hero input. It is narrow, its width cannot be set, and its own wireframes show the prompt and the sentence truncated ('Describe what you wa…').",
   "[hig] The leading gutter dot. It sits in the unread-dot position used by Mail, Reeder and Podcasts and will be read as 'unread'. Use the thin gutter bar that echoes the reader's margin bar.",
   "[hig] A live status line inside the text storage. Mutating the storage on every tick shifts character ranges under the user's selection and the tint mapping. Keep the header static, and put the live status in the foot.",
   "[hig] `.contentTransition(.numericText())` on `navigationSubtitle`. A window subtitle is not a SwiftUI Text, so it will just swap.",
   "[hig] An unsure current hit gaining a half-alpha yellow fill. It makes unsure look found. Mark the current hit by bar weight, not fill.",
   "[hig] Merging the tints of adjacent found paragraphs into one slab. It breaks the one-mark-per-paragraph match with the strip. Keep separate rounded rects with a 4 pt gap.",
   "[hig] Status spread over five places (subtitle, notice row, tail rows, header line, find-bar counter), with none visible mid-article. Also kill the hit counter and chevrons that exist only while the find bar is open.",
   "[hig] Nine identical `pin` glyphs down the sidebar. Use numbered glyphs that double as the Cmd-digit hint.",
   "[hig] The opacity curve clamp(p/0.6, 0.35, 1). It draws p=0.45 at 0.75 and over-claims a one-in-three band.",
   "[instrument] One field with two scopes. The carried sentence vanishes while asking the article, the scope is signalled only by a glyph swap, and Return means run, open or re-light depending on invisible state.",
   "[instrument] The selection highlight pinned to the first slot while rows slide beneath it. Selection belongs to an item, never a slot. Also kill the 250 ms row slides on every 200 ms snapshot.",
   "[instrument] Esc as Back from the reader, and the four-rung Esc ladder. A double Esc to close the ask loses the article and then the search. Use Cmd-[ for Back; Esc only closes transient things and clears the field.",
   "[instrument] The custom NSTextField subclass in the toolbar with an in-field pin glyph and no clear button. A hand-rolled control inside system glass is where imitation shows. Use NSSearchField plus a standard toolbar button.",
   "[instrument] The two-column drill-in as the app structure. It is a search-results page with a Back button. It hides the ranked list while reading, drops the preview PRODUCT.md specifies, and never shows list marks and lit paragraphs together.",
   "[instrument] The 2 pt tertiary grey thread on every unchecked paragraph. Use 1 pt in separator or quaternary colour. Also kill the code-block corner radius that implies a filled box behind code.",
   "[all] Shipping any of these specs without the saturation state. The addendum makes it mandatory, and broad searches open into it most of the time."
  ]
 },
 {
  "scores": [
   {
    "direction": "hig",
    "taste": 7,
    "nativeFeel": 9,
    "clarity": 6,
    "feasibility": 7.5,
    "notes": "Cheapest chrome and the most native screenshot, but its three 'stock' status mechanisms are the weak part. (1) `.searchable(placement: .toolbar)` gives a fixed-width trailing field: the spec's own wireframes truncate both the prompt ('Describe what you wa…') and the user's sentence, it collapses to a button in narrow windows, and it cannot intercept Down-arrow or a second Return, so keyboard step 2 is unbuildable without wrapping NSSearchField anyway. The product's one clear input ends up looking like Mail's keyword search. (2) `navigationSubtitle` is an NSWindow string: `.contentTransition(.numericText())` cannot apply to it, and it truncates ('Newest 300 of 6,2…') in the spec's own reader wireframe. (3) The counting status line lives inside the NSTextView storage: editing storage about ten times a second while the tints depend on TextKit 2 fragment frames invites relayout and scroll jumps, the line scrolls out of sight, and the hit counter exists only while the find bar is open. List status is split over subtitle, a top notice row and tail rows. The yellow gutter dot reads as Mail's unread dot. Robust and worth keeping: `findBarView` above content (a real NSTextFinderBarContainer slot, not an overlay, and it fixes the title overlap), system sidebar collapse, 1180x760 sizing with a 480 pt reader minimum, the 'Show N less likely' fold, a persistent stronger tint for the current hit, one adjustable strip element for VoiceOver, notice priority order. Selected-row y anchoring on a SwiftUI List is still a trap. The addendum's saturation state (over 35% found) is missing."
   },
   {
    "direction": "editorial",
    "taste": 8.5,
    "nativeFeel": 7.5,
    "clarity": 8,
    "feasibility": 7,
    "notes": "Best base. The running foot is the cheapest and most robust status surface of the three: a plain SwiftUI row under each column (build it as VStack + Divider + foot rather than safeAreaInset, so the hosted NSScrollView never runs under it). It is never truncated by toolbar items, never scrolls away, and it keeps the text storage immutable after load, which is what frame-driven TextKit 2 tints want. The foot-ask is a field swap inside that row: no overlay on NSTextView, no content shift, title overlap impossible, and counter plus chevrons stay available to the mouse at all times. The wrapped NSSearchField as a wide principal item is work every direction needs anyway (Down-arrow, second Return) and delivers the one clear input with the full prompt visible. Solid / dotted / hairline / nothing is the most legible four-state grammar in greyscale, and the list bar echoes the margin bar, so one article teaches the list. Its traps are all peripheral and deletable: 'top visible row pinned, content grows upward' (custom scroll anchoring on SwiftUI List), link colour on hover inside NSTextView, the 700 ms tint swell (per-frame redraw of the text view), custom auto-collapse at 1180 pt with a 660 pt reader minimum and a 1320x860 default that nearly fills Ben's 13-inch Air, a search floor of 0.25 that lists the measured noise band, the recents menu, one accessibility button per strip mark. Native-feel costs: serif list titles on paper and a find field at the bottom (Xcode's bottom filter fields are the precedent); the list font is one constant, so let Ben pick from a screenshot. A 1 pt separatorColor rule is too faint for a paragraph that stays unchecked after settle. The saturation state is missing, but the foot is its natural home: 'Most of this article is about this (94 of 159 paragraphs). Find something narrower.' with Cmd-F opening the field in the same spot. Prototype note for whichever wins: /Users/benjamintordjman/Documents/CODING_PROJECTS/beam/spikes/swift/Sources/readerprobe/Reader.swift runs ensureLayout over the whole document plus an O(n^2) range lookup on every drawBackground; cache fragment frames per layout pass and drive fades by invalidating only the animating paragraph rects, with no timer under Reduce Motion."
   },
   {
    "direction": "instrument",
    "taste": 7,
    "nativeFeel": 6,
    "clarity": 6,
    "feasibility": 5,
    "notes": "The most minimal first screen and the best window fit for a 13-inch Air, and list-to-article push has an Apple News precedent, but it is the most custom build and the least robust. One field with two scopes is a modal input whose only cue is a glyph swap; it needs a two-text state machine plus hand-rolled first-responder moves between a toolbar item and the hosted NSTextView (SwiftUI FocusState does not cover that path reliably). The NSTextField subclass with an inline pin glyph and no clear button means custom cell geometry, focus ring and glass matching, and removing the clear button is anti-native and leaves mouse users no way back to chronological order. Rows sliding for 250 ms on a 200 ms snapshot tick is the named trap: overlapping NSTableView animations and selection jitter. Holding the highlight on the first slot while items change under it makes Return open a moving target. The toolbar hit-counter group appears, disappears and changes width ('5 hits' to '2 of 5'), which re-lays out the toolbar and nudges the principal field. Swapping list and reader in one column needs a custom transition plus focus and scroll restoration, loses arrowing through results while reading, and loses the one screenshot that explains the product (ranked list beside a lit article). Esc as Back in a four-deep ladder is not Mac behaviour. The counting status line sits in the scrolling header, the same storage-mutation problem as hig. Good parts to lift: delayed dim on search start, second Return opens the top result, 5 pt minimum for hollow strip ticks, tertiaryLabelColor thread for unchecked, focus the field at launch, 'Stops at $0.50 a day'. Saturation state is missing."
   }
  ],
  "winner": "editorial",
  "graft": [
   "hig: the 'Show N less likely' fold row with the list floor at the measured 0.45 (addendum), replacing editorial's list-everything-from-0.25 and the hidden 'Esc shows everything'. Build it as a selectable enum-ID row in the List; Return triggers it.",
   "hig: window sizing and collapse: default 1180x760, minimum 900x560, reader minimum 480 pt with flexible side margins, sidebar collapse left entirely to the system.",
   "hig: current hit as a persistent state: found tint one step stronger via a 150 ms alpha step (an unsure current hit gets half-alpha fill), kept alongside editorial's thicker bar and wider strip mark. Replaces the swell.",
   "hig: strip geometry rule: the strip is a subview of the NSScrollView positioned in tile(), inset by the legacy scroller width so neither scroller style covers it, with a 16 pt hit target and no track.",
   "hig: the strip as one adjustable accessibility element ('Hit 2 of 5, found'; increment and decrement move between hits) instead of one button per mark.",
   "hig: gutter mark turns white on an emphasised selection (read `backgroundProminence` in the row) and goes full opacity under Increase Contrast. Editorial does not say what yellow does on the accent highlight.",
   "hig: one message at a time in the foot, by priority: key rejected, daily limit, offline, exclusions note.",
   "hig: SF Pro list row (13 medium title, 11 secondary meta, system inset separators) kept behind one constant next to editorial's New York 15 row; show Ben both screenshots and let him choose. New York stays for the reader and the preview either way.",
   "hig: app icon small sizes: at 16 and 32 px reduce to three bars with the middle one lit and drop the strip.",
   "hig: `findBarView` with `findBarPosition = .aboveContent` as the ready fallback if Ben rejects a find field at the bottom; it is a real NSScrollView slot, not an overlay, and matches PRODUCT.md.",
   "instrument: delayed dim on search start: dim the old list to 40% only if nothing has arrived after 150 ms; cached results swap in with no dim, which keeps the offline-repeat MUST instant and avoids a flash.",
   "instrument: a second Return in the field opens the top result (the PRODUCT.md aha), handled in the NSSearchField delegate's doCommandBy, selecting the row at that moment rather than holding a highlight on the first slot during streaming.",
   "instrument: hollow strip ticks get a 5 pt minimum height so a 1 pt stroke still reads as hollow; solid ticks keep 3 to 4 pt.",
   "instrument: tertiaryLabelColor at 1.5 to 2 pt for paragraphs still unchecked after the run settles (MUST 6 needs failures to be noticed); keep editorial's faint separatorColor hairline only while pending.",
   "instrument: at launch, focus the field unless a selection is restored, so the placeholder and caret are the only instruction.",
   "instrument and hig: Settings copy 'Stops at $0.50 a day' and 'Key works. Stored in your Keychain.'",
   "instrument, only if time allows: New / Earlier as two plain system List sections in pin lists, so the sidebar's new-count has a visible referent.",
   "Gap in all three, must be added to the winner: the saturation state from the addendum. When more than 35% of checked paragraphs are found, draw no tints and no strip marks, and the reader foot reads 'Most of this article is about this (94 of 159 paragraphs). Find something narrower.' Cmd-F then opens the ask field in that same foot."
  ],
  "kill": [
   "hig: `.searchable(placement: .toolbar)` as the hero input. Fixed-width trailing field, truncates prompt and sentence in the spec's own wireframes, collapses to a button when narrow, cannot intercept Down-arrow or a second Return.",
   "hig: list status in `navigationSubtitle` with `.contentTransition(.numericText())`. A window subtitle cannot take a content transition and it truncates beside toolbar items.",
   "hig and instrument: a counting status line inside the NSTextView text storage. Header text in storage must be static (title, byline, text-only note, hairline); everything that changes goes in the foot.",
   "hig: three list status surfaces (subtitle, top notice row, tail status rows). One foot per column replaces them; only the fold row and 'Check 1,200 older' remain as rows.",
   "hig: the yellow gutter dot. A leading dot in an Apple list means unread; use editorial's thin bar that echoes the margin bar.",
   "hig: hit counter visible only while the find bar is open; mouse users get no next-hit control.",
   "hig: merging adjacent found tints into one shape. The merged rect changes shape mid-fade when a neighbour lands in a later 100 ms batch; separate rects with the 4 pt gap fall out of the paragraph spacing for free.",
   "editorial: 'top visible row pinned, insertions grow the content upward'. Custom scroll anchoring on a SwiftUI List is a trap. Replace with: apply snapshots freely until the user touches the list (arrow, click or scroll); after that, hold late arrivals and apply them in one unanimated snapshot when the run settles (at most about two seconds later), keeping the selected row visible.",
   "editorial: body links that change colour on hover inside NSTextView (tracking areas plus attribute mutation). Use static `linkTextAttributes`: ink with a tertiary underline, system pointing-hand cursor.",
   "editorial: the 700 ms tint swell, and instrument's 0.24 to 0.42 pulse. Both need per-frame redraws of the text view for decoration; the persistent current-hit state says more.",
   "editorial: custom sidebar auto-collapse at 1180 pt, the 660 pt reader minimum and the 1320x860 default. They fight the user's own toggle and nearly fill a 13-inch Air.",
   "editorial: listing every search result from 0.25 up. EVIDENCE.md measures the 0.25 to 0.60 band at 10% precise; it produces a long tail of faint rows.",
   "editorial: the NSSearchField recents menu of the last ten sentences. It is an extra control and it stores sentences in defaults outside the SQLite file; pins are the history.",
   "editorial: one accessibility button per strip mark.",
   "instrument: one field with two scopes. A modal input signalled only by a glyph swap, with a two-text state machine and manual first-responder plumbing.",
   "instrument: swapping list and reader in a single column, and Esc as Back in a four-deep ladder. Loses the list-beside-lit-article view and needs custom transition, focus and scroll restoration.",
   "instrument: rows sliding down over 250 ms on every 200 ms snapshot. Overlapping NSTableView animations and selection jitter; only per-row opacity on appear is safe.",
   "instrument: holding the highlight on the first slot while items change beneath it. Return opens a moving target, and in three panes the preview would flicker.",
   "instrument: the custom NSTextField subclass with an inline pin glyph and no clear button. Custom cell geometry, focus ring and glass matching for less native behaviour; use NSSearchField plus an adjacent pin button.",
   "instrument: the toolbar hit-counter group that appears, disappears and changes width. It re-lays out the toolbar and shifts the principal field.",
   "All three: spoken 'Found.' / 'Unsure.' paragraph prefixes as a day-one item. They need NSTextView accessibility overrides; ship the Hits rotor and the adjustable strip element first.",
   "Prototype habit to drop before any of this: calling ensureLayout on the whole document and enumerating every fragment inside drawBackground. Cache frames per layout pass or the 100 ms judgment ticks and fades will stutter on 150 to 400 paragraphs."
  ]
 }
]

# Critic: slop

Note: the spec arrived cut off and starts partway through section 3, so I could not review layout, type or the colour tokens.

1. **A tint plus a left bar is the docs-site callout box.**
   - A rounded tinted box with a coloured left border is the most generic AI-made component there is. The bar also repeats what the fill already says.
   - Fix: found = tint only. The margin slot holds exceptions only (hollow bar, rail).
   - Current hit = the stronger tint alpha, plus a 1 pt `hitInk` outline under Increase Contrast.
   - Drop the amber bar from the icon too.

2. **The list mark is a meter in disguise.**
   - Its four opacity steps are unreadable. In a search every listed row wears a mark, so the mark says nothing.
   - Fix: mark at p ≥ 0.60, no mark below. A search with zero found rows is then a calm, unmarked list.
   - With marks doing that job, delete the full-width hairline in All Items. Keep the full-width rule for one meaning only: new since the pin was last viewed.

3. **There are two ticking counters.**
   - "212 of 300 checked" swapping every 200 ms is a progress bar in words.
   - Fix: a static "Checking 300 items" in the list foot and "Checking 84 paragraphs" in the reader foot. Show the running count only on a stall over 3 s or on failure.

4. **The reader foot says everything twice.**
   - "5 hits" sits beside "3 found, 2 unsure in 84 paragraphs checked". "Hits" is a noun Ben sees nowhere else in the window.
   - Fix: the resting foot reads "3 found, 2 unsure". The chevrons and "2 of 5" appear after the first Cmd-G or when the ask field is open.
   - Show "in 84 paragraphs checked" only when the run is incomplete or nothing was found.
   - Move the saturation parenthetical to a help tag. Remove "Done", because Esc already closes the field.

5. **The paper carries chrome.**
   - "Text only. 4 images, 2 tables in the original." is a standing apology on every article.
   - "Return to read" is an instruction in the article body, against the spec's own rule that status lives only in the foot.
   - Fix: end the byline with "Open Original (4 images, 2 tables)", and move the Return hint to the foot.

6. **The sidebar is icon soup.**
   - Up to nine pin rows show the identical pin glyph. There are six cute source-kind glyphs (`graduationcap` for arXiv), and `y.square` is a brand logo.
   - Fix: pin rows are text only under their header. Sources get one neutral glyph or none.

7. **Warning triangles will be routine.**
   - EVIDENCE.md shows Reddit returning HTTP 429 on a second request, so failing sources are expected.
   - Fix: a failing source's title goes secondary, and the triangle appears only after 24 h of failure. Drop the pin triangle, because the foot already says "31 not checked. Retry".

8. **"Show 262 less likely" brings back a row PRODUCT.md cut.**
   - It offers rows at roughly 10% precision, with a number on it.
   - Fix: remove it. Esc already shows everything.

9. **Streaming blinks and shoves.**
   - The dim at 150 ms followed by the cross-fade at 350 ms is a flicker. Rank-order insertion pushes rows under the eye five times a second.
   - Fix: no dim. Hold the old list until the first paint. After that, insert new rows only below the fold and merge the rest when the run settles.

10. **The strip's invisible proportional-scroll zone is a hidden control beside the scroller.**
    - Fix: only the marks are clickable.

11. **The only alert and the only red guard source removal, while pins vanish unconfirmed.**
    - A pin is a hand-tuned sentence, and Cmd-Delete removes it with no way back.
    - Fix: add Undo Remove for both pins and sources, and delete the alert.

12. **The icon is the generic genre.**
    - "Document with grey lines" is what every notes and reader app uses, and this one carries four ideas.
    - Fix: keep the lines and one lit paragraph.
    - Check how Tahoe treats it (the grey plate behind older icon shapes) and how warm white glares in a dark Dock. A hand-made .icns has no dark or tinted variant.

13. **Several states are missing.**
    - Key sheet cancelled: a sentence sits in the field over an unranked list, so the foot needs "Add a key to search. Open Settings".
    - A selected source that is empty, or failed with no items.
    - An article with no paragraphs Beam can judge, for example all code.
    - Clicking a source mid-search: what the field shows.
    - The title wrap limit and absent dates in result rows.
    - How the foot wraps at minimum window width.
    - The daily limit reached mid-article.
    - The exclusions note is too long for the list foot; use "Exclusions, amounts and dates aren't judged."

I did not use the Figma MCP server. It needs authorising from the claude.ai connector settings, or with `claude mcp` or `/mcp` in an interactive session.

Files read:
- /Users/benjamintordjman/Documents/CODING_PROJECTS/beam/docs/PRODUCT.md
- /Users/benjamintordjman/Documents/CODING_PROJECTS/beam/docs/EVIDENCE.md

# Critic: native

I only received the spec from mid-section 3 onward, so I have not seen the window layout or toolbar sections. Any issue marked * below may already be settled there.

1. **The menu bar is under-specified.** The spec lists only Add Source, a Find submenu, View and Item. Specify the full set:
   - **Beam:** About, Settings… ⌘,, Services, Hide Beam, Hide Others, Show All, Quit.
   - **File:** Add Source… ⌘N, one toggling Pin Sentence/Unpin Sentence ⌘D, Remove Pin / Remove Source… ⌘⌫ (title follows the sidebar selection), Refresh ⌘R, Close Window ⌘W. "Remove" and "Pin Sentence" do not belong in a menu called Item.
   - **Edit:** Undo, Redo, Cut, Copy, Paste, Select All, Find ▸, Speech ▸.
   - **View:** Show/Hide Sidebar ⌃⌘S, All Items, the pins, the text size commands, Enter Full Screen.
   - **Item:** Open Original ⌘O, Copy Link, Share ▸.
   - **Window:** Minimize, Zoom, the system tiling items, "Beam", Bring All to Front.
   - **Help:** the system search only, since there is no Help Book.
   - Set `NSWindow.allowsAutomaticWindowTabbing = false`.
   - Decide what ⌘W does. I suggest the app keeps running, and a Dock click or Window > Beam reopens the window.

2. **The Find submenu breaks convention.** Keep the standard items: "Find by Meaning…" ⌘F, "Find Next" ⌘G, "Find Previous" ⇧⌘G, "Use Selection for Find" ⌘E (fills the ask field from the selection) and "Jump to Selection" ⌘J. Set `usesFindBar = false` and override `performTextFinderAction:` so the literal finder never appears.

3. **Writing Tools can add "Summarise" to the reader's context menu and the Edit menu.** Set `writingToolsBehavior = .none` on the text view and on both search fields.

4. **⌘⌫ collides with delete-to-line-start in the search field, which is focused at launch.** Enable Remove only while the sidebar is first responder with a pin or source selected. A disabled menu item lets the key fall through to the field. It must never fire from list focus.

5. **Esc clearing the sentence from anywhere is destructive.** Mail and Notes clear only when the field is focused. Elsewhere, Esc should only close the ask field. In `doCommandBy`, skip Return and Esc handling while `hasMarkedText()` is true, because AZERTY dead keys produce marked text.

6. **Several shortcuts need attention.**
   - Search-everything is ⌥⌘F in Mail and Notes. Make that the listed key and keep ⌘L as an alternate.
   - The ⌘+/⌘− pair has no reset. Add "Actual Size" with no key equivalent, because ⌘0 is already All Items, as in Mail.
   - Bind both "=" and "+" for bigger text.
   - Test every shortcut on AZERTY.

7. ***SwiftUI `.searchable` exposes no delegate, so `doCommandBy` cannot work with it.** Use an AppKit `NSSearchToolbarItem` with `sendsWholeSearchString = true`. Set its preferred width and the minimum window width so it never collapses to a magnifier button.

8. **A clicked row that shows only "Return to read" contradicts every three-pane Mac app.** A mouse click should open the article. Arrow-key browsing can stay preview-only. When an item is opened from the field, move focus to the list, so that Space pages the article and does not type a space.

9. **The opaque hairline feet are pre-Tahoe status bars.** Hand-drawn feet will clip against the 26 pt window corners. Use `NSSplitViewItem` bottom-aligned accessory view controllers (in SwiftUI, `safeAreaBar(edge: .bottom)`) with a hard scroll-edge effect. Reading text will pass under the glass toolbar items. Use the hard top scroll-edge effect there, and do not try to make the toolbar opaque.

10. **The hit counter's borderless chevrons are a custom control.** Use a small momentary `NSSegmentedControl` with `chevron.left` and `chevron.right`, as NSTextFinder does.

11. **Tail rows both select and act, which is conflicted.** Make them unselectable `.link` buttons below the table. Pressing Down past the last row should focus them.

12. **With the sidebar collapsed, the ⌘N popover has no anchor.** Reveal the sidebar first.

13. **The removal alert needs its defaults specified.** Cancel should be the default button and Esc should cancel. Set `hasDestructiveAction` on Remove.

14. **Settings needs its conventions spelled out.**
    - Use the `Settings` scene, titled "Beam Settings", with the minimise and zoom buttons disabled.
    - Use a columns form. The toggle should be a checkbox, not a switch.
    - Commit the key when editing ends, not on each keystroke.
    - "Open Settings" should use the `openSettings` environment action.

15. ***The window title is never specified.** The title should be the current sidebar selection. Otherwise, hide it on purpose.

16. **The strip's proportional click duplicates the scroller.** It also ignores the system "Click in the scroll bar to" preference. Clicks that land off a mark should do nothing.

17. **A user highlight colour or accent colour of Yellow makes text selection vanish on a found tint.** Keep the tint alpha clearly below the selection's, and test with Highlight set to Yellow.

18. **Sharing and drag-and-drop are missing.**
    - Add `NSSharingServicePicker.standardShareMenuItem` to the Item menu and the row context menu.
    - ⌘C on a selected row should copy its link.
    - Rows should drag out as URLs.
    - A URL dropped on the sidebar should add a source.

19. **The app icon is `.icns` only.**
    - It has no dark, tinted or clear variants and no glass rendering.
    - The 824 pt body is the Big Sur grid, so check it against the macOS 26 template or the system may re-mask it.
    - Build the `.icon` into an `Assets.car` once on a Mac that has Xcode, or in CI. Commit that file, set `CFBundleIconName`, and keep the `.icns` as the fallback.

The Figma MCP server (plugin:figma:figma) has not been authorised, and I cannot authorise it from this non-interactive session. Do that in the claude.ai connector settings, or with `/mcp` in an interactive session. This review did not need it.

Files read:
- /Users/benjamintordjman/Documents/CODING_PROJECTS/beam/docs/PRODUCT.md
- /Users/benjamintordjman/Documents/CODING_PROJECTS/beam/docs/EVIDENCE.md

# Critic: a11y

1. **The not-checked state is nearly invisible.**
   - `separatorColor` is about 1.2:1 on paper and `tertiaryLabelColor` about 1.9:1. The settled rail and the 2 pt strip segment mark an honest state, and both fail 3:1.
   - Fix: the pending rail may stay faint because it is transient. Draw the settled rail and strip segment in `secondaryLabelColor` at 2 pt, and in `labelColor` under Increase Contrast.

2. **The hollow bar is hard to tell from the solid bar at 4 pt.**
   - A 1 pt stroke leaves a 2 pt hole. That hole closes on 1x external displays and for users with low acuity, and the bar then also resembles the rail.
   - Fix: make the hollow bar 6 pt wide with a 1.5 pt stroke in all modes, and 8 pt when it is the current hit. Hollow strip marks are at least 8 × 6 pt.

3. **Increase Contrast raises the alpha of yellow, which adds almost no luminance contrast.**
   - A yellow tint on white is about 1.2:1 at any alpha.
   - Fix: under Increase Contrast or Differentiate Without Colour, draw a 1 pt solid `hitInk` outline on found rects. The list mark shows strength by height (half or full) at full opacity, not by alpha.

4. **The current hit is shown only by a 2 pt width change.**
   - That is the only cue for unsure hits and under Reduce Motion.
   - Fix:
     - Make the current bar 8 pt.
     - Call `UAZoomChangeFocus` with the paragraph rect so Zoom follows Cmd-G.
     - Post "Hit 2 of 5, unsure" to VoiceOver on every jump, because the foot change is silent.

5. **Inline accent text buttons rely on colour alone.**
   - With a Graphite accent, "Retry" is grey inside a grey sentence. With a Yellow accent it is hit-coloured. The targets are about 14 pt tall.
   - Fix:
     - Use real `NSButton`s in the key loop, with a 24 pt minimum hit height.
     - Underline them when Differentiate Without Colour is on or the accent is Graphite or Yellow.
     - Give the chevrons and Done 24 × 24 pt hit rects.

6. **A Yellow system highlight hides the selection inside found paragraphs.**
   - Fix: when the hue of `selectedTextBackgroundColor` is in the yellow family, set the reader's `selectedTextAttributes` background to `unemphasizedSelectedTextBackgroundColor`.

7. **VoiceOver cannot tell the states apart while reading.**
   - Fix:
     - Label rotor items "Found, {first words}" or "Unsure, …", each with a `targetRange`.
     - Add a "Not checked" rotor when a run settles with gaps.
     - Remove the strip from accessibility and the key loop when it is empty or the article is saturated.
     - Expose either the strip or the counter label to VoiceOver, not both.

8. **List streaming moves rows under the VoiceOver cursor.**
   - The VoiceOver cursor is not an arrow, click or scroll, so the hold never triggers and rows insert beneath it.
   - Fix: when `NSWorkspace.shared.isVoiceOverEnabled`, apply one snapshot at settle. Announce "38 items. Top: {title}. Return to read", because the auto-selection is otherwise silent.

9. **Several flows have no keyboard path.**
   - Pin reorder is drag-only. Add Item > Move Pin Up and Move Pin Down (Option-Cmd-arrows), plus accessibility custom actions.
   - Copy Link and Copy Feed URL exist only in context menus. Add them to the Item menu.
   - Popover: specify that Down moves into the catalog, Return adds, and focus stays. Announce the status line and "Added".
   - Announce the key sheet's status line.
   - Define the strip's focus ring around its 16 pt lane.

10. **Some information is available only in help tags.**
    - Selecting a failing source puts "Couldn't refresh: {reason}. Retry" in the foot.
    - Cmd-D at nine pins puts "Nine pins maximum" in the foot.
    - The bar-slot help rect covers the full 20 pt slot × paragraph height, re-registered on each layout pass.

11. **Text size is unspecified and applies only to the reader.**
    - Fix:
      - Use persisted steps from 15 to 28 pt.
      - Define the measure as 66 characters so it scales with the font.
      - Set the bar slot and outsets in em.
      - Add Actual Size.
    - The list, preview and foot scale in step with the reader, or use `NSFont.preferredFont(forTextStyle:)`.
    - The foot is the sole status channel and the least legible text. Set error and actionable sentences in `labelColor` at 13 pt.

12. **Reduce Motion removes the fades, leaving about 20 abrupt pops over two seconds.**
    - Opacity is not vestibular motion.
    - Fix: keep the fades, or coalesce to one paint per viewport plus one at settle. Only the scroll becomes instant.
    - Reduce Transparency needs nothing further, since Beam draws no glass.

The Figma MCP server (plugin:figma:figma) is unauthorised and cannot run OAuth here. Authorise it in the claude.ai connector settings or with `/mcp` in an interactive session. This review did not need it.

Files read:
- /Users/benjamintordjman/Documents/CODING_PROJECTS/beam/docs/PRODUCT.md
- /Users/benjamintordjman/Documents/CODING_PROJECTS/beam/docs/EVIDENCE.md

