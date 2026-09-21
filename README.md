# Beam

One sentence, two zoom levels: rank everything you follow against a plain-language sentence, then open any
article with the matching paragraphs already lit. Native macOS 26 (SwiftUI + AppKit), powered by TypeSafe's Jev.
It never summarises, rewrites or answers — it ranks, and it points at source text.

## Where things are
| Path | What |
|---|---|
| `docs/PRODUCT.md` | v1 scope: three PO drafts, four critics, measured addendum (the addendum wins) |
| `docs/DESIGN.md` | design spec: three directions, three judges, three critics |
| `docs/ARCHITECTURE.md` | module lanes, public APIs, schema, build order |
| `docs/EVIDENCE.md` | every number we measured, and the spike that produced it |
| `mock/` | native design mock with real captured data — `./mock/show.sh [lit|saturated|plain] [light|dark]` |
| `spikes/` | throwaway experiments (Swift + Python) the evidence came from |
| `tooling/make-app.sh` | wraps a SwiftPM build into a signed .app (no Xcode on this machine) |

Status: specs, evidence and mock done. No product code yet — waiting for Ben's go.
