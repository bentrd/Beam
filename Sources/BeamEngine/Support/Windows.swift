import Foundation

/// How much of a library one action looks at. Every number here is a promise made in PRODUCT.md or DESIGN.md.
public enum Windows {
    /// "Cache first, then the newest 300 round-robin across sources."
    public static let newest = 300
    /// What one press of "Check 1,200 older" adds.
    public static let older = 1_200

    /// How many items a list without a sentence carries. A chronological reader is read from the top, and a
    /// snapshot of 50,000 items would cost megabytes on every repaint; the foot still counts everything.
    public static let chronological = 2_000

    /// How far back a pin looks for the items it has already found. A pin judges the newest 300 like a search,
    /// but it keeps listing what it found on earlier days, so it reads further back than it judges.
    public static let pinList = 2_000

    /// "If Ben allows it, the top three found rows are judged ahead, 40 passages each."
    public static let prejudgedRows = 3
    public static let prejudgedPassages = 40

    /// How often pins are brought up to date while Beam is running (PRODUCT.md section 5).
    public static let pinRefresh = Duration.seconds(30 * 60)

    /// One unanimated snapshot every 200 ms for lists, every 100 ms for the reader (DESIGN.md section 5).
    public static let listTick = Duration.milliseconds(200)
    public static let readerTick = Duration.milliseconds(100)

    /// A failed extraction is remembered this long before Beam tries the page again: long enough that reopening
    /// a dead link is instant, short enough that a site that was down at lunch reads by dinner.
    public static let failedArticleLife: TimeInterval = 3_600
}
