import Foundation

public enum ResolveOutcome: Sendable {
    case found([SourceCandidate])
    case alreadyAdded(Source)
    case notFound
}

public enum AddOutcome: Sendable {
    case added(Source)
    case alreadyAdded
    case failed(String)
}

public enum PinOutcome: Sendable {
    case pinned(Pin)
    case alreadyPinned(Pin)
    /// "Nine pins maximum"
    case limitReached
}

/// The one seam between pixels and everything else. `BeamEngine` implements it for real;
/// `FakeBackend` (in BeamUI) implements it from captured data so the UI can be built and reviewed on its own.
///
/// Streams: `sidebar()` lives for the life of the app. `list(_:)` and `open(itemID:carrying:)` each finish the
/// stream returned by the previous call of the same method, cancel its outstanding work, and start fresh.
/// Snapshots arrive on the main actor, at most one every 200 ms for lists and every 100 ms for the reader.
@MainActor
public protocol BeamBackend: AnyObject {
    // Key, privacy, spend
    func keyStatus() async -> KeyStatus
    /// nil or empty removes the key. Validates a candidate before storing; returns the attempt's outcome.
    /// A failed attempt preserves the current connection; read keyStatus() for the active credential's status.
    func setKey(_ key: String?) async -> KeyStatus
    func dollarsToday() async -> Double
    /// Settings ▸ "Light up top results before I open them". Off by default.
    var prejudgesTopResults: Bool { get set }

    // Sidebar
    func sidebar() -> AsyncStream<SidebarSnapshot>
    func catalog() -> [CatalogEntry]
    func resolve(_ input: String) async -> ResolveOutcome
    func addSource(_ candidate: SourceCandidate) async -> AddOutcome
    func removeSource(id: Int64) async
    func retrySource(id: Int64) async
    func pin(sentence: String) async -> PinOutcome
    func removePin(id: Int64) async
    func movePin(id: Int64, by offset: Int) async
    func markPinViewed(id: Int64) async
    /// Undo for Remove Pin, Remove Source and Mark All as Read, newest first. Returns the menu title of what was undone, or nil.
    func undo() async -> String?
    var undoTitle: String? { get }
    /// Fetch every source now; also retries anything not checked.
    func refresh() async

    // Lists
    func list(_ request: ListRequest) -> AsyncStream<ListSnapshot>
    func checkOlder()
    func retryList()
    func setRead(_ read: Bool, itemIDs: [Int64]) async
    func markAllRead(in scope: ListScope) async

    // Reader
    /// Title, snippet and "Return to read" for a selected row. Sends nothing, fetches nothing.
    func preview(itemID: Int64) -> ReaderSnapshot?
    /// Opens the item (marks it read), extracts the article and judges passages against `sentence`, viewport first.
    func open(itemID: Int64, carrying sentence: String?) -> AsyncStream<ReaderSnapshot>
    /// Find by Meaning on the open article. nil restores the carried sentence's marks from the cache at once.
    func find(_ sentence: String?)
    func setViewport(firstVisible: Int, lastVisible: Int)
    func retryReader()
    func closeReader()
}
