# Beam

One sentence, two zoom levels.

Type what you want to read. Beam ranks everything you follow against that sentence, and when you open an
article the paragraphs that match are already lit. It never summarises, rewrites or answers — it ranks, and
it points at the source.

Native macOS 26 (SwiftUI + AppKit), powered by TypeSafe's Jev. No backend, no account, your own API key.

## Running it

```
tooling/make-app.sh release      # builds build/Beam.app
open build/Beam.app
```

A first launch seeds Hacker News, MLX releases and Apple Machine Learning Research, and works as a plain
reader with no key at all. Add a key in Settings to search by meaning.

`-fake YES` runs the whole window against captured data — no network, no key, no database — which is how the
design is reviewed. `-look light|dark` pins the appearance for screenshots.

## Checks

There is no Xcode on this machine, so there is no XCTest: each lane has a check executable, and `beam-eval`
is the acceptance suite, one subcommand per "V1 MUST" in `docs/PRODUCT.md`.

```
swift build
.build/debug/check-jev && .build/debug/check-store && .build/debug/check-feeds && .build/debug/check-extract
.build/debug/beam-eval all              # add --offline to skip the network and the key
```

987 assertions: jev 177 · store 216 · feeds 194 · extract 190 · eval 190 offline / 210 live.

## Where things are

| Path | What |
|---|---|
| `docs/PRODUCT.md` | v1 scope. The addendum and owner decisions at the end override the text above them |
| `docs/DESIGN.md` | The design spec. Section 11 is the owner's addendum |
| `docs/ARCHITECTURE.md` | Module lanes, the `BeamBackend` contract, schema, build order |
| `docs/EVIDENCE.md` | Every number we measured, and the spike that produced it |
| `Sources/BeamModels` | The contract: value types, UI snapshots, `BeamBackend`, the check harness |
| `mock/show.sh` | The approved design mock, on captured data |
| `spikes/` | The throwaway experiments the evidence came from |

## The things worth knowing

- **Judgments are cached by what was judged.** The cache key is the text hash plus the framed sentence plus the
  model id, so an edited title is "not checked" rather than silently stale.
- **"Not checked" is never "nothing".** A failed or pending judgment is drawn differently from a judgment that
  came back negative, and the foot counts what was not reached.
- **Saturation.** When a sentence describes the whole article, more than 35% of paragraphs come back found and
  highlighting stops meaning anything; Beam draws no marks and says "Most of this article is about this."
- **Maths.** Pages leave both a rendered copy and the TeX source; the reader is text, so the source is turned
  into Unicode (`∂f/∂θ₁`, `Attention(Q,K,V)=softmax(QK^T/√dₖ)V`). No backslash ever reaches the reader.
- **The judging order is only an order.** Items whose words echo the sentence are judged first so good rows
  arrive sooner; every item in the window is judged either way.
