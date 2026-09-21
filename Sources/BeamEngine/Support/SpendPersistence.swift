import BeamJev
import BeamStore

/// The store's spend ledger is exactly the shape the judge's breaker persists through, so adopting it here is
/// the whole wiring: the day's tokens survive a relaunch and "About $0.04 today" tells the truth after one.
extension SpendLedger: SpendPersisting {}
