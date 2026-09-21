import BeamModels
import SwiftUI

/// PLACEHOLDER — the reader lane replaces this file. The initializer is the contract: keep it.
public struct ReaderPane: View {
    private let snapshot: ReaderSnapshot?

    /// - Parameters:
    ///   - snapshot: nil means nothing is selected: blank paper and a blank foot.
    ///   - textSize: the reader body size in points (eight steps, 15…28, default 17).
    public init(snapshot: ReaderSnapshot?, textSize: CGFloat, controller: ReaderController, actions: ReaderActions) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Text(snapshot?.item.title ?? "").frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
