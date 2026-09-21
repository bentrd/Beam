# PART 2: Decisions log

**slop**
1. Accepted: found is tint only and the margin slot holds exceptions. The icon bar is gone. This departs from the "plus solid margin bar" wording in PRODUCT §6.
2. Accepted: one full-strength mark at p ≥ 0.60 and none below. The All Items divider is deleted and pin lists are unmarked. The full-width rule means "new" only.
3. Accepted: the feet read "Checking 300 items" and "Checking 84 paragraphs". The running count shows only after a 3 s stall or on failure.
4. Accepted:
   - The resting foot reads "3 found, 2 unsure".
   - The counter appears after the first jump, which includes a strip click.
   - The saturation count moves to the help tag and the accessibility value.
   - "Done" is removed. The clear button and Esc close the field.
5. Accepted: the byline ends "Open Original (4 images, 2 tables)", and the Return hint moves to the reader foot.
6. Accepted: the sidebar is text only, with no icons on pins, sources or All Items. This departs from the "kind symbol" in PRODUCT §4.
7. Partly accepted: the triangle appears only after 24 hours, and the pin triangle is dropped. The secondary-title cue is rejected because it is low-contrast and colour-only. The foot names the failure on selection.
8. Accepted: "Show less likely" is removed. "Check 1,200 older" becomes a foot button, so tail rows are gone.
9. Accepted: there is no dim and the old list holds. After the first paint only below-screen appends show, and the rest merge once at settle.
10. Accepted: only the marks are clickable.
11. Accepted: Undo covers pins and sources, and the alert and its red are deleted. This departs from "sources confirm" in PRODUCT §10.
12. Accepted: the icon is lines plus one lit paragraph, with a Dock check in light and dark on macOS 26.
13. Accepted: all the listed states are specified.
    - cancelled key sheet;
    - an empty source;
    - an all-code article;
    - a source clicked mid-search;
    - the title wrap and absent dates;
    - the foot wrapping at narrow widths;
    - the daily limit arriving mid-article.
    - The exclusions note is shortened.

**native**
1. Accepted: the full menu bar is in section 10. The Item menu is dropped in favour of the six standard menus, and ⌘W keeps the app running.
2. Accepted: the Find items use standard names, with ⌘E and ⌘J. The literal finder is suppressed.
3. Accepted: Writing Tools are off in every field and text view.
4. Accepted: Remove is enabled only with sidebar focus.
5. Accepted: Esc clears only from the field. Return and Esc are ignored during marked text.
6. Accepted: ⌥⌘F is listed with ⌘L as the alternate. Actual Size has no key, ⌘= and ⌘+ are both bound, and shortcuts are tested on AZERTY.
7. Accepted: the field is an `NSSearchToolbarItem` sending whole strings, with width floors.
8. Accepted: a click opens the row and arrows preview. Focus moves to the list on open. YouTube rows are exempt from single-click opening. This departs from PRODUCT §6.
9. Accepted: the feet are bottom-aligned accessories with hard scroll-edge effects, top and bottom.
10. Accepted: the counter uses a small momentary segmented control with left and right chevrons.
11. Accepted in spirit: tail rows no longer exist. Check Older is a foot button in the key loop.
12. Accepted: the sidebar is revealed before the popover opens.
13. Moot: the alert is removed (slop 11).
14. Accepted: the Settings conventions are adopted as written.
15. Accepted: the title is set to the sidebar selection and hidden in the toolbar. The foot names a selected source.
16. Accepted: clicks off a mark do nothing.
17. Accepted through a11y 6.
18. Accepted:
    - Share goes in File and in the row context menu.
    - ⌘C copies the link.
    - Rows drag out as URLs.
    - A URL dropped on the sidebar opens the Add Source popover.
19. Partly accepted: the icon gets a macOS 26 grid and Dock check. The prebuilt `Assets.car` is rejected for v1 because the brief fixes SwiftPM only, with no asset catalogs.

**a11y**
1. Accepted: the settled rail and strip segment are 2 pt `secondaryLabelColor`, and `labelColor` under Increase Contrast.
2. Accepted:
   - The hollow bar is 6 pt wide with a 1.5 pt stroke.
   - It is 8 pt when current.
   - Hollow strip marks are 8 × 6 pt minimum.
3. Accepted: found rects gain an outline under Increase Contrast or Differentiate Without Colour, with no alpha rise. The height-coded list mark is rejected as a two-step meter. The mark is binary at full strength.
4. Accepted: the current unsure bar is 8 pt, Zoom focus follows each jump, and VoiceOver announces each jump.
5. Accepted: text buttons are real buttons with a 24 pt hit height and conditional underlines.
6. Accepted: a yellow-family highlight swaps the reader selection to the unemphasised colour.
7. Accepted:
   - Rotor items are labelled, and a "Not checked" rotor is added.
   - The counter is exposed to VoiceOver.
   - The strip is hidden from accessibility and removed from the key loop.
8. Accepted: with VoiceOver on, the list applies one snapshot at settle, with the announcement.
9. Accepted: Move Pin Up and Move Pin Down are added, with custom actions. Copy goes through Edit > Copy, and the popover keys and announcements are specified. The strip focus ring is moot.
10. Accepted: the failing-source reason and "Nine pins maximum" go in the foot. Help rects cover the full slot.
11. Partly accepted:
    - Accepted: steps from 15 to 28 pt, em-scaled geometry, Actual Size, and error sentences in `labelColor`.
    - Rejected: scaling the list with ⌘+, because Mac apps scale content and not chrome.
    - Rejected: a 13 pt error size, because the foot must not change height between states.
12. Accepted: the fades stay under Reduce Motion, and only the scroll becomes instant.

---

**Notes**
- The spec reached me cut off before section 3's colour tokens. Sections 1 and 2 and the start of section 3 are rewritten here to fit the rest. Their headings ("Principles", "Window and layout", "Visual language") are reconstructions, so check them against the original.
- The Figma MCP server (plugin:figma:figma) has not been authorised, and this non-interactive session cannot run OAuth. Authorise it in the claude.ai connector settings, or with `claude mcp` or `/mcp` in an interactive session. It is unavailable until then. This revision did not need it.
- Files read:
  - /Users/benjamintordjman/Documents/CODING_PROJECTS/beam/docs/PRODUCT.md
  - /Users/benjamintordjman/Documents/CODING_PROJECTS/beam/docs/EVIDENCE.md