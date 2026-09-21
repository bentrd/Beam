import BeamModels
import QuartzCore

/// What one paragraph should show for the active sentence. Found, unsure, nothing and not checked differ by shape:
/// a fill, a hollow bar, no mark at all, or a rail.
enum ReaderMark: Equatable {
    case none
    case found
    case unsure
    /// Not checked yet, while the run is going: the 1 pt rail.
    case pending
    /// Still not checked after the run settled: the 2 pt rail.
    case unchecked

    var isHit: Bool { self == .found || self == .unsure }
    var isRail: Bool { self == .pending || self == .unchecked }
}

/// The marks of a whole article for one sentence, derived from a snapshot. Pure, so the rules can be read in one place.
struct ReaderMarkPlan: Equatable {
    /// Marks of a different sentence (or article) replace the old ones at once; within one sentence they fade.
    let sentenceKey: String
    /// By passage index. Passages that show nothing are absent.
    let marks: [Int: ReaderMark]

    static let empty = ReaderMarkPlan(sentenceKey: "", marks: [:])

    init(sentenceKey: String, marks: [Int: ReaderMark]) { self.sentenceKey = sentenceKey; self.marks = marks }

    init(snapshot: ReaderSnapshot) {
        guard snapshot.phase == .ready, let sentence = snapshot.sentence else { self = .empty; return }
        let holdsHits = snapshot.isSaturated || Self.isHoldingHits(snapshot)
        var marks: [Int: ReaderMark] = [:]
        for (index, passage) in snapshot.passages.enumerated() where passage.isJudgeable {
            if let probability = snapshot.checks[index]?.probability {
                guard !holdsHits else { continue }
                switch Bands.passage(probability) {
                case .found: marks[index] = .found
                case .unsure: marks[index] = .unsure
                case .nothing: break
                }
            } else {
                // Pending, failed and stale all read "not checked"; never "nothing".
                marks[index] = snapshot.isRunning ? .pending : .unchecked
            }
        }
        self.init(sentenceKey: "\(snapshot.item.id)\u{1F}\(sentence)", marks: marks)
    }

    /// No hit is painted until enough paragraphs are checked to know the article is not saturated,
    /// so a broad sentence never flashes yellow over the whole page before going calm.
    static func isHoldingHits(_ snapshot: ReaderSnapshot) -> Bool {
        let judgeable = snapshot.passages.indices.filter { snapshot.passages[$0].isJudgeable }
        let checked = judgeable.filter { snapshot.checks[$0]?.isChecked ?? false }.count
        return checked < min(Bands.saturationMinimumChecked, judgeable.count)
    }
}

/// One opacity on its way somewhere, easing out. Values are computed from the clock at draw time, so a missed timer
/// tick can delay a repaint but can never leave a mark at the wrong strength.
struct ReaderFade {
    private(set) var to: CGFloat
    private var from: CGFloat
    private var start: CFTimeInterval
    private var duration: CFTimeInterval

    static func settled(_ value: CGFloat) -> ReaderFade { ReaderFade(to: value, from: value, start: 0, duration: 0) }

    /// A new fade that starts from wherever this one is now, so a reversal never jumps.
    func heading(to target: CGFloat, over duration: CFTimeInterval, now: CFTimeInterval) -> ReaderFade {
        ReaderFade(to: target, from: value(at: now), start: now, duration: duration)
    }

    func value(at now: CFTimeInterval) -> CGFloat {
        guard isActive(at: now) else { return to }
        let remaining = 1 - CGFloat(max(now - start, 0) / duration)
        return from + (to - from) * (1 - remaining * remaining)
    }

    func isActive(at now: CFTimeInterval) -> Bool { duration > 0 && now < start + duration }
}

/// Everything animated about one paragraph's marks. Motion is opacity only: shapes never slide or grow,
/// they cross-fade (the widening of a current unsure bar is the 8 pt bar fading in over the 6 pt one).
struct ReaderMarkLayer {
    /// The hit being shown or faded out. Kept until its opacity reaches zero.
    var hit: ReaderMark = .none
    var hitOpacity = ReaderFade.settled(0)
    var rail: ReaderMark = .none
    var railOpacity = ReaderFade.settled(0)
    /// 0 resting, 1 current.
    var emphasis = ReaderFade.settled(0)

    static let hitFadeIn: CFTimeInterval = 0.25
    static let railFadeOut: CFTimeInterval = 0.15
    static let emphasisStep: CFTimeInterval = 0.15

    func isActive(at now: CFTimeInterval) -> Bool {
        hitOpacity.isActive(at: now) || railOpacity.isActive(at: now) || emphasis.isActive(at: now)
    }

    /// True once there is nothing left to draw, so the layer can be dropped.
    func isSpent(at now: CFTimeInterval) -> Bool {
        !isActive(at: now) && hitOpacity.to == 0 && railOpacity.to == 0 && emphasis.to == 0
    }

    mutating func show(_ mark: ReaderMark, animated: Bool, now: CFTimeInterval) {
        let hitTarget: CGFloat = mark.isHit ? 1 : 0
        if mark.isHit, hit != mark {
            // A different shape starts from nothing; shapes do not morph.
            hit = mark
            hitOpacity = animated ? ReaderFade.settled(0).heading(to: 1, over: Self.hitFadeIn, now: now) : .settled(1)
        } else if hitOpacity.to != hitTarget {
            hitOpacity = animated ? hitOpacity.heading(to: hitTarget, over: Self.hitFadeIn, now: now) : .settled(hitTarget)
        }
        if mark.isRail {
            // Rails are present from the first frame of text: they never fade in.
            rail = mark
            railOpacity = .settled(1)
        } else if railOpacity.to != 0 {
            railOpacity = animated ? railOpacity.heading(to: 0, over: Self.railFadeOut, now: now) : .settled(0)
        }
    }

    mutating func setCurrent(_ isCurrent: Bool, animated: Bool, now: CFTimeInterval) {
        let target: CGFloat = isCurrent ? 1 : 0
        guard emphasis.to != target else { return }
        emphasis = animated ? emphasis.heading(to: target, over: Self.emphasisStep, now: now) : .settled(target)
    }
}
