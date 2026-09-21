# Beam — design spec

## 1. Principles

- The content is the interface. Beam has one field, one list and one page of text.
- Beam points and never speaks. It ranks rows and tints source paragraphs. It shows no summaries, scores or explanations.
- Found, unsure, nothing and not checked look different. They differ by shape as well as colour, and none of them shouts.
- Beam uses stock controls, system type, system colours and system glass. It draws only the paper marks, the strip and the list mark.
- Work shows as rows arriving and grey rails retracting. Nothing on screen moves once Ben can read it.

## 2. Window and layout

- There is one window with three columns: sidebar, list and reader. There are no tabs and no second window, and automatic window tabbing is off.
- **Sizes**
  - The default size is 1180 × 760 and the minimum is 820 × 520.
  - The sidebar is 220 pt. The list is 320 pt, resizable from 280 to 400. The reader takes the rest.
  - The sidebar collapses by itself below 960 pt.
- **Title.** The window title is set to the sidebar selection, for Mission Control, the Window menu and VoiceOver. It is hidden in the toolbar.
- **Toolbar** (system glass)
  - It holds the sidebar toggle, the search field as the centred principal item, and the pin button beside the field.
  - The field is an AppKit `NSSearchToolbarItem` that sends whole strings only.
  - Its preferred width is 420 pt and it is never narrower than 260 pt, so it never collapses to a magnifier button.
- **Reader**
  - The measure is 66 characters, centred.
  - Each side keeps at least 44 pt for the mark slot and the strip.
  - The title starts 32 pt below the toolbar edge, and nothing floats near it.
- **Feet**
  - The list and the reader each have a one-line foot. At narrow widths it grows to two lines and never truncates.
  - The feet are bottom-aligned split-view accessories with the hard scroll-edge effect. The system therefore fits them to the window corners, and they read as opaque.
  - The top edge also uses the hard scroll-edge effect, so text never shows through toolbar glass.

## 3. Visual language

**Type**
- List rows
  - The title is 13 pt system. It runs to two lines at most, then truncates at the tail.
  - "source · age" is 11 pt secondary. When there is no date, the source appears alone.
- Feet are 12 pt. Status is secondary. Errors and any sentence with a button are in `labelColor`.
- Reader and preview use New York.
  - The title is 28 pt semibold.
  - The body is 17 pt with 26 pt leading and 14 pt paragraph spacing.
  - Headings are 20 pt semibold.
  - The byline is 12 pt system secondary.
  - Code is SF Mono 14 pt with no box.
  - Quotes are indented with no bar.
  - Links are ink, underlined.
- Text size
  - There are eight persisted steps from 15 to 28 pt. The default is 17, and Actual Size returns to it.
  - Text size scales the reader and the preview. The measure, the mark slot and the outsets scale with it. The values below are for 17 pt.
  - Chrome uses system text styles.

**Colour**
- Paper is `textBackgroundColor`, ink is `labelColor`, and hairlines are `separatorColor`. Controls take the user's accent colour.
- `hitFill` is #FFD60A at 0.22, or 0.40 for the current hit. In dark mode the alphas are 0.16 and 0.30.
- `hitInk` is #9A6B00, about 4.7:1 on white, and as pale yellow (#FFE066) in dark mode.
- The pending rail is `separatorColor`, because it is transient. A rail still unchecked after the run settles is `secondaryLabelColor`.
- Beam uses no red, green or orange and no second hit colour. The one warning glyph is monochrome secondary.

**Materials**
- Glass appears only where the system draws it: sidebar, toolbar items, search field, sheet, popover and menus. `.glassEffect()` is never called.
- The list, the reader, the ask field, the strip and every empty state are opaque.
- Reduce Transparency uses the system fallback and changes nothing of Beam's own drawing.

**Hit states.** The margin slot sits 20 pt left of the text, and it holds exceptions only. Text is full ink in every state.

| State | Paragraph | Margin slot | Strip (16 pt lane) |
|---|---|---|---|
| Found | `hitFill` rounded rect, radius 6, outset 12 pt horizontally and 5 pt vertically. One rect per paragraph, so neighbours keep a 4 pt gap. | none | solid 6 pt mark, true paragraph height, 3 pt minimum |
| Unsure | none | hollow bar, 6 pt wide, 1.5 pt `hitInk` stroke | hollow mark, 8 pt wide, 6 pt minimum, 1.5 pt stroke |
| Nothing | none | none | none |
| Not checked | none | 1 pt rail while pending; 2 pt `secondaryLabelColor` rail if still unchecked after settle | 2 pt centred segment, same colour |
| Current | a found tint steps to the stronger alpha | an unsure bar widens to 8 pt | the mark widens to 10 pt, toward the text |
| Saturated | none | none; rails retract as usual | none |

- Headings and code carry no marks and no rails.
- **List mark**
  - It is a solid 4 × 12 pt `hitInk` mark in the row gutter.
  - It is drawn at full strength on rows at p ≥ 0.60 and never below. There are no steps and no fading.
  - It takes the selected text colour on an emphasised selection.
- **Increase Contrast or Differentiate Without Colour**
  - Found rects gain a 1 pt `hitInk` outline, or 2 pt when current.
  - The settled rail and the strip segment become `labelColor`.
  - The pending rail steps up one label colour.
  - Tint alphas do not change.
- **Yellow highlight.** When the system highlight colour is in the yellow family, the reader's selection uses `unemphasizedSelectedTextBackgroundColor`. Selection then stays visible on a tint.

## 4. Components

**Search field**
- Anatomy: the system magnifier, the text and the system clear button.
- It has no recents, suggestions, scopes or tokens. Nothing is sent while typing.
- Writing Tools are off here and in every other field and text view.
- Return with changed text runs the sentence. It cancels any running queue, clears the list selection and blanks the reader.
- Return with unchanged text opens the selected row.
  - If no row is selected, it opens the row shown at the top at that key-down.
  - Focus then moves to the list, so Space pages the article.
- When a run settles, the top row becomes selected if the field still has focus and nothing is selected.
  - The selection is unemphasised.
  - The reader previews the row. No requests are sent.
- Down moves focus to the list. Up from the first row returns to the field.
- Esc clears the sentence only while the field has focus. The clear button does the same.
- Return and Esc are ignored while there is marked text, because AZERTY dead keys produce it.
- With no key, Return raises the sheet and the sentence waits in the field.
- Selecting a pin fills the field with its sentence. Editing it and pressing Return makes a new unpinned search in All Items.
- Clicking a source during a search keeps the sentence in the field. The list filters locally in the same order, and nothing is sent.
- At launch the field has focus, unless a selection is restored.

**Pin button**
- It shows `pin` when the sentence is unpinned and `pin.fill` when pinned, in the standard toolbar tint.
- It is enabled whenever there is a submitted sentence.
- At nine pins it pins nothing. The list foot says "Nine pins maximum" until the next action.
- Pinning adds the sidebar row and selects it.

**Result row**
- Anatomy: mark, title, then "source · age".
- States: unopened, opened (secondary title), and the system's selected and selected-inactive.
- It has no badges, percentages, hover states or accessories.
- A click, Return or Space opens the row.
- Arrow keys preview the row (title and snippet) and send nothing.
- A YouTube row never opens on a single click. Return or a double-click opens the browser.
- ⌘C copies the link. Rows drag out as URLs.
- The context menu offers Open Original, Copy Link and Share.
- **Ordering**
  - Searches list rows at p ≥ 0.45, by p rounded to 0.05, then by date. Rows at p ≥ 0.60 carry the mark.
  - Pins list rows at p ≥ 0.60 by date, newest first, with no marks.
    - The separator under the last row new since the pin was last viewed runs full width.
    - A full-width separator has no other meaning anywhere.
  - With no sentence, All Items shows this week's pin hits first, marked. The rest follow by date, unmarked, with no divider.
  - Unchecked items are never listed as if ranked. The foot counts them.

**List foot**
- It shows one message at a time, in this priority order:
  1. no key;
  2. key rejected;
  3. daily limit;
  4. offline;
  5. run stopped after repeated errors;
  6. "N not checked. Retry";
  7. the selected source's failure;
  8. the exclusions note;
  9. the count.
- The count may end in "Check 1,200 older", which extends the run. There are no tail rows.
- Text buttons
  - They are real buttons in the key loop, with a 24 pt hit height.
  - They are underlined when Differentiate Without Colour is on, or when the accent is Graphite or Yellow.

**Sidebar**
- The sidebar is text only, in this order: All Items, Pins (the header is hidden when empty), Sources, and Add Source at the bottom.
- **Pin row**
  - It shows the sentence, tail-truncated. The full sentence is in the help tag.
  - `.badge(n)` counts rows new since the pin was last viewed. Leaving the pin marks it viewed.
  - Dragging, or Move Pin Up and Move Pin Down, reorders pins. The order sets ⌘1 to ⌘9.
  - The context menu offers Remove Pin.
  - Pins are not editable.
- **Source row**
  - It shows the title.
  - Transient failures show nothing. After 24 hours of failure, a trailing warning glyph appears.
  - Selecting a failing source puts the reason and Retry in the foot.
  - The context menu offers Retry, Copy Feed URL and Remove Source. ⌘C copies the feed URL.
  - A click filters the list locally and sends nothing.
- **Removal**
  - Removal has no alert. Undo restores the pin, or the source with its items, until Beam quits.
  - ⌘⌫ is live only while the sidebar has focus.

**Add Source popover**
- ⌘N or the bottom button opens a 320 × 360 popover. If the sidebar is collapsed, it is revealed first.
- A focused field sits over a hairline, with the live-filtered catalog below.
- Down moves into the catalog. A click or Return adds a source.
  - The row gains a checkmark.
  - The source appears in the sidebar at once.
  - The popover and the focus stay for more.
- One secondary line under the field carries the inline status.
- A URL dropped on the sidebar opens the popover with that URL already running.
- Esc closes it.

**Reader header**
- Order: title, then "source · date · Open Original (4 images, 2 tables)".
  - The parenthetical is secondary text and is not part of the link.
  - It appears only when something was left out.
- A hairline is drawn beneath it. The hairline is not a character.
- The header is static text in the storage, so it selects, copies and is read in order.
- Storage is never mutated after load.
- It has no hero image, avatar or reading time.

**Paragraph marks**
- They are painted in `drawBackground`, so native selection draws above them.
- Fragment frames are cached once per layout pass.
- Beam never lays out or enumerates fragments inside a draw.
- A fade invalidates only the rect of the paragraph that is fading.
- They have no hover and no click behaviour. Text selection is sacred.
- Help tags cover the full slot by the paragraph height. They read "Unsure. Read this yourself." and "Not checked".

**Strip**
- It is a 16 pt lane at the trailing edge, inset by the legacy scroller width.
- It has no track or border. It is invisible unless there are marks.
- Positions are true to layout, taken from the cached frames.
- A click within 12 pt of a mark jumps to that paragraph. Any other click does nothing.
- A jump lands the paragraph's top at 30% of the viewport height.
- It is a mouse-only map. It is outside the key loop and hidden from accessibility, because Find Next is its keyboard equivalent.

**Reader foot and counter**
- The status sentence sits on the left and the counter on the right.
- The counter appears after the first jump, or while the ask field is open.
  - It reads "2 of 5", beside a small momentary segmented control with `chevron.left` and `chevron.right`, as the system find bar has.
  - The control has a 24 pt hit height.
  - It counts found and unsure paragraphs together, in document order, and wraps at the ends.
- While the current hit is unsure, the status reads "Unsure. Read this yourself."

**Ask field**
- ⌘F swaps the status text for a stock search field whose placeholder reads "Find by meaning".
  - It opens empty.
  - Reopened on the same article, it holds the last question with its text selected.
  - ⌘E opens it filled with the selection.
- Return re-lights this article only. A further Return or ⌘G moves to the next hit.
- While it is open, the counter slot carries the short status.
- Esc or the clear button closes it. It also closes if it loses focus while empty.
- On closing, the carried sentence's marks return from the cache at once.
- The literal text finder never appears.

**Saturation**
- Beam paints no found marks until 24 paragraphs have been checked, or all of them if there are fewer.
- From then on, the article is saturated once found ÷ checked exceeds 0.35.
  - Beam then draws no tints, no bars and no strip marks.
  - The counter is hidden, and Find Next and Find Previous are disabled.
  - Rails retract as usual.
- The foot shows the saturation sentence.
  - Its tail, "Find something narrower.", is a text button that opens the ask field.
  - The paragraph count lives in the help tag and the accessibility value.
- Saturation is sticky for the run.
  - If the share falls back to 0.35 or below when the run settles, marks fade in once.
  - If marks were already showing when the share crosses 0.35, they fade out once.
- There is no glyph and no colour. It is a calm sentence, never an error.

**Empty and failed states.** Each is one centred secondary line with at most one text button, and no symbols.
- No sources: "No sources yet." with Add Source.
- First fetch: "Getting your sources", shown only if nothing has arrived after 1 s.
- Empty source: "No items yet."
- Nothing found: the line, and the foot offers the older items.
- No selection: blank paper, and the foot stays blank.
- A failed article shows the title, the snippet and one line.
- An article that is all code shows "Code not checked." in the foot.
- Errors and offline
  - They always appear as a foot sentence, plus rails in the article.
  - They never appear as alerts, banners or colours.
- When the daily limit arrives mid-article, unchecked paragraphs keep their rails and the foot says so.

**Key sheet**
- It is 440 pt wide and holds the headline, the disclosure, the retention link, a secure field and "Get a key".
- The disclosure gains the top-three clause only when the Settings toggle is on.
- Buttons
  - Cancel (Esc) keeps the sentence in the field. The foot then reads "Add a key to search. Open Settings".
  - Continue is the default, and it is disabled while the field is empty.
- Continue validates the key, with one status line under the field.
- On success the sheet closes and the waiting sentence runs.

**Settings**
- It is the system Settings scene, titled "Beam Settings", with the minimise and zoom buttons off.
- It is a columns form. The toggle is a checkbox.
- The key commits when editing ends.
- "Open Settings" uses the system action.

## 5. Motion

Motion is opacity only. Nothing slides, scales, glows or staggers.

**List streaming**
- A judgment is final on arrival. Rows never reorder among themselves, and the only change is insertion.
- Cached sentences repaint at once.
- Otherwise the old list holds at full strength. There is no dim.
- The first paint waits for 8 listable rows or 350 ms, whichever comes first. If nothing is listable at 350 ms, it waits for the first listable row. It then cross-fades in over 180 ms.
- After the first paint
  - A new row appears at once only if it ranks below every row on screen. It fades in over 150 ms.
  - All other rows are held.
  - They merge in one unanimated snapshot when the run settles, and they fade in.
  - Rows on screen therefore move once at most.
- If Ben has touched the list, the selected row keeps its y position at the merge.
- With VoiceOver on, the whole list applies as one snapshot at settle.
- The foot reads "Checking 300 items" and does not tick.
  - It cross-fades to its settled sentence over 120 ms.
  - A running count appears only after a 3 s stall or on failure.
- There is no spinner and no skeleton.

**Reader**
- Title and byline appear at once, in their final position. The body fades in over 200 ms when extracted.
- "Getting the article" shows only if extraction takes more than 1 s.
- Rails are present from the first frame of text.
- Judgments apply on a 100 ms tick, viewport first.
  - Tints and marks fade in over 250 ms with ease-out.
  - Rails fade out over 150 ms.
- The foot reads "Checking 84 paragraphs" and does not tick.
- The visible effect is a grey rail retracting while yellow settles, finishing in about two seconds.
- The article never scrolls by itself.

**Other motion**
- A jump to a hit is a 300 ms ease-in-out scroll.
  - A 150 ms step then brings in the current state.
  - That state persists. It is not a pulse.
- The ask swap is a 120 ms cross-fade with no size change.
- The sheet, popover, sidebar and pin symbol replacement use system defaults.

**Reduce Motion**
- Jumps are instant.
- The fades stay, because opacity is not motion.
- No timers run for decoration.

## 6. Copy

**Case rule.** Everything that reads as a sentence uses sentence case. Commands use macOS title-style capitals.

**Field and toolbar**
- Prompt: "Describe what you want to read"
- Help tags: "Pin this sentence", "Unpin this sentence"

**Sidebar**
- Labels: "All Items", "Pins", "Sources", "Add Source"
- Context menus: "Remove Pin", "Retry", "Copy Feed URL", "Remove Source"
- Help tag: "Couldn't refresh: {reason}"

**List foot**
- "64 items"
- "64 items in r/swift"
- "Checking 300 items"
- "212 of 300 checked"
- "300 items checked"
- "Newest 300 of 6,200 checked. Check 1,200 older"
- "31 not checked. Retry"
- "Stopped after repeated errors. Retry"
- "Couldn't refresh: {reason}. Retry"
- "Offline. Showing what was already checked."
- "Daily limit reached. Resets at midnight."
- "TypeSafe rejected this key. Open Settings"
- "Add a key to search. Open Settings"
- "Exclusions, amounts and dates aren't judged."
- "Nine pins maximum"

**List body**
- "Nothing found in 300 items checked"
- "Getting your sources"
- "No sources yet."
- "No items yet."
- Row context menu: "Open Original", "Copy Link", "Share"

**Reader header**
- "Open Original (4 images, 2 tables)"

**Reader foot**
- "Return to read"
- "Return to open in your browser"
- "Getting the article"
- "Checking 84 paragraphs"
- "38 of 84 checked"
- "3 found, 2 unsure"
- "Nothing found in 84 paragraphs checked"
- "Matched by title. Nothing found in 84 paragraphs checked"
- "61 of 84 checked. Retry"
- The suffix "Code not checked."
- "Most of this article is about this. Find something narrower."
  - Help tag: "94 of 159 paragraphs"
- "Unsure. Read this yourself."
- "Daily limit reached. Resets at midnight."
- Counter: "2 of 5"
- Help tags: "Find Next", "Find Previous", "Not checked"

**Ask field**
- "Find by meaning"
- "Checking"
- "Nothing found in 84 checked"
- "Most of this article is about this"

**Failed article**
- "Beam couldn't get the article text. Open Original."

**Add Source popover**
- Prompt: "Feed, site, subreddit or channel URL"
- Status lines: "Looking for a feed", "No feed found at this address", "Already added", "Added"

**Key sheet**
- Headline: "Add your TypeSafe key"
- Disclosure: "To judge meaning, Beam sends your sentences, your sources' titles and snippets, and paragraphs of articles you open, to TypeSafe with your key."
  - With the toggle on, it reads "…articles you open or that rank in the top three, to TypeSafe…".
- Closing line: "Nothing has been sent yet."
- Links: "How TypeSafe keeps data", "Get a key"
- Field placeholder: "TypeSafe key"
- Buttons: "Cancel", "Continue"
- Status lines: "Checking…", "TypeSafe rejected this key", "Can't reach TypeSafe. Check your connection."

**Settings**
- "TypeSafe key:"
  - "Key works. Stored in your Keychain."
  - "No key. Beam works as a plain reader."
  - "Clear the field to remove the key."
- "Privacy:"
  - the disclosure text;
  - "How TypeSafe keeps data";
  - "Light up top results before I open them";
  - "Sends paragraphs of the top three results before you open them."
- "Usage:"
  - "About $0.04 today"
  - "Beam stops at $0.50 a day."

**Menus.** Menu titles are listed in section 10.

## 7. Iconography and app icon

**SF Symbols**
- Pin button: `pin` and `pin.fill`
- Add Source: `plus.circle`
- A source failing for more than 24 hours: `exclamationmark.triangle`, in monochrome secondary
- Counter: `chevron.left` and `chevron.right`
- Catalog row already added: `checkmark`
- The sidebar toggle, the magnifiers and the clear buttons are the system's.
- Sidebar rows, empty states, the sheet and Settings carry no symbols.

**App icon**
- The icon is a miniature of the reader, drawn with Core Graphics rounded rectangles only and packed with `iconutil`.
- The body is flat warm white (#FAFAF7), with a 1 px inner edge at 8% black.
- Six full-round grey bars (#C9C9C4) form two three-line paragraphs. The last line of each is shorter.
- The second paragraph sits on a rounded rect of #FFD60A at 55%.
- The icon has no margin bar, strip tick, gradient, letterform or glow.
- At 16 and 32 px it reduces to three bars with the middle one lit.
- Before shipping, check it by screenshot in a light and a dark Dock on macOS 26.
  - The body is drawn to the macOS 26 icon grid.
  - If the system plates or re-masks it, the body is adjusted.
- Version 1 ships the `.icns` only.

## 8. Accessibility and keyboard

**VoiceOver**
- A result row reads "{title}, {source}, {age}, 3 of 38", plus "opened" where it applies.
  - The mark is hidden.
  - Rank is spoken. A probability never is.
- A pin row reads "{sentence}, 3 new", and offers Move Up and Move Down as custom actions.
- A failing source reads "{name}, couldn't refresh, {reason}".
- The pin button reads "Pin sentence" or "Unpin sentence".
- A rotor named "Marked paragraphs" lists "Found, {first words}" and "Unsure, {first words}", each with its range.
- A "Not checked" rotor appears when a run settles with gaps.
- Every jump posts "2 of 5, unsure" and moves Zoom focus to the paragraph.
- The counter label is exposed. The strip is not.
- Each foot posts one polite announcement when a run settles, never a count-up.
  - A search says "38 items. Top: {title}. Return to read."
- The popover and sheet status lines are announced.

**Contrast**
- Body text stays `labelColor` on every tint, above 10:1 in both modes.
- `hitInk` keeps at least 3:1 on paper.
- The four states differ by shape: a fill, a hollow bar, a rail, or nothing.
- The fill gains its outline under Differentiate Without Colour, so the states survive greyscale.

**Keyboard flow**
1. ⌥⌘F, or ⌘L, focuses the field. Type, then press Return to run.
2. Return again opens the top row, and focus moves to the list.
3. Down moves focus into the list. The arrow keys preview and send nothing.
4. Return or Space opens an item. Space then pages through it.
5. ⌘G and ⇧⌘G walk the marked paragraphs, wrapping at the ends.
6. ⌘F opens the ask field, and Return re-lights the article.
7. Esc closes the ask field. In the search field it clears the sentence. It never navigates.

**Rules**
- Every shortcut is a menu item, listed in section 10.
- Tab order runs field, sidebar, list, reader, with each foot's buttons after its pane.

## 9. What we refuse to do

- We add no glass of our own, and no glass sits over paper. Nothing floats near the title.
- We add no second field at the top of the window, and no find bar that pushes the page.
- Status lives nowhere but the foot. It never appears in a banner, toast, alert, window subtitle, notice row or the text storage.
- A found paragraph gets no margin bar, because a tint plus a bar is a callout box. Marks are never dashed or dotted, nothing glows or pulses, and quotes have no bar.
- Lists carry no dots, rings, badges, percentages, band words or graded marks.
- We add no tail rows and no "less likely" row.
- The sidebar carries no icons. There are no favicons and no brand glyphs.
- There is no warning glyph for transient failures.
- New York stays out of the list.
- Rows on screen never move during a run. The highlight is never held on a slot. Nothing opens or scrolls by itself.
- We use no spinners, progress bars, skeletons, shimmer, ticking counts or "thinking" text.
- We use no second hit colour, no accent-coloured hits and no yellow controls. Unsure paragraphs never get a tint.
- We never dim reading text or a stale list. We never tint a saturated article, and saturation never looks like an error.
- We add no hover effects, cards, boxed Settings groups, code-block boxes, or uppercase or letter-spaced labels.
- We add no recents, suggestions, scopes, tokens or search-as-you-type. There is no Run or Stop button. A new Return is the stop.
- We add no confirmation alerts. Undo is the safety net.
- We add no onboarding, tour, tips or sample search.
- We add no chat, summaries, Writing Tools, "why it matched", "AI" wording, sparkles, gradients, mascot or emoji. The app icon carries no letter B.
- We never say "Nothing found" about anything Beam has not checked, and we never write "No matches".

## 10. **Menus**

Beam has the six standard menus and no custom top-level menu.

- **Beam**
  - About Beam
  - Settings… ⌘,
  - Services
  - Hide Beam ⌘H
  - Hide Others ⌥⌘H
  - Show All
  - Quit Beam ⌘Q
- **File**
  - Add Source… ⌘N
  - Open Original ⌘O
  - Share ▸
  - Pin Sentence or Unpin Sentence ⌘D (one toggling item)
  - Move Pin Up ⌥⌘↑
  - Move Pin Down ⌥⌘↓
  - Remove Pin or Remove Source ⌘⌫
    - The title follows the sidebar selection.
    - It is enabled only while the sidebar has focus, so the key otherwise falls through to the text field.
  - Refresh ⌘R, which also retries
  - Close Window ⌘W
- **Edit**
  - Undo ⌘Z, which includes "Undo Remove Pin" and "Undo Remove Source"
  - Redo ⇧⌘Z
  - Cut
  - Copy ⌘C, which copies text, the selected row's link, or the selected source's feed URL
  - Paste
  - Select All
  - Find ▸
  - Speech ▸
- **Find ▸**
  - Search All Items ⌥⌘F, with ⌘L as an unlisted alternate
  - Find by Meaning… ⌘F
  - Find Next ⌘G
  - Find Previous ⇧⌘G
  - Use Selection for Find ⌘E
  - Jump to Selection ⌘J
- **View**
  - Show Sidebar or Hide Sidebar ⌃⌘S
  - All Items ⌘0
  - the pin sentences, ⌘1 to ⌘9
  - Make Text Bigger ⌘+, also bound to ⌘=
  - Make Text Smaller ⌘−
  - Actual Size
  - Enter Full Screen
- **Window**
  - Minimize ⌘M
  - Zoom
  - the system tiling items
  - the window, listed by its title
  - Bring All to Front
- **Help**
  - the system search field only
- **Rules**
  - There are no New Window items and no tab items.
  - ⌘W closes the window and Beam keeps running. A Dock click or the Window menu reopens it.
  - The four article Find items are disabled when no article is open.
  - Find Next and Find Previous are also disabled in a saturated article.
  - Writing Tools appear in no menu.
  - Every shortcut is tested on an AZERTY layout.

---

## 11. Owner addendum: read and unread

Ben asked for read/unread back. It uses what the design already has and adds nothing visual:
- Unread title: `labelColor`. Read title: `secondaryLabelColor` (the existing "opened" state). No dot, no bold, no icon.
- Sidebar: sources and All Items carry the system `.badge(n)` unread count; at zero the badge is absent. Pin badges keep their meaning.
- Menus: File ▸ `Mark as Read` / `Mark as Unread` ⇧⌘U (one toggling item), File ▸ `Mark All as Read` ⌘K (undoable: "Undo Mark All as Read");
  View ▸ `Hide Read Items` ⌥⌘R (checkmark item, persisted). Row context menu gains `Mark as Read` / `Mark as Unread`.
- VoiceOver: unread rows append "unread"; the "opened" wording is dropped.
- Dark-mode note from the mock review: the found tint reads slightly olive on dark paper. Use #FFD60A at 0.20 (0.34 current) over a paper of `textBackgroundColor`, and verify by screenshot.
