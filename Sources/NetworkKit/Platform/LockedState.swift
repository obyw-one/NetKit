//
//  LockedState.swift
//  NetKit
//
//  Spec c8fa126c BR-L-03: `Sources/NetworkKit/Platform/` is the ONE subtree in
//  the portable NetKit target where a platform condition may appear, mirroring
//  `Sources/CoreKit/Platform/`. The T-L-03/T-L-04 ratchet
//  (`NetKitPortabilityRatchetTests`) excludes it BY PATH, never by filename
//  ([[a-ratchet-scopes-a-folder-subtree-never-a-filename-list]]).
//
//  The condition here selects a LOCK PRIMITIVE, not a capability: both arms are
//  compiler-checked `Sendable` and neither is `@unchecked`, so the fleet rule
//  that turns a lock box into an actor does not apply
//  ([[unchecked-sendable-on-a-recorder-is-a-symptom-make-the-callback-async]]).
//  What DID apply was its location: a condition in the middle of the portable
//  tree is how a second one arrives unnoticed.
//
//  Mutable state behind a lock, `Sendable` BY CONSTRUCTION.
//
//  A class that holds mutable fields and a hand-rolled `NSLock` can only claim
//  `Sendable` with `@unchecked`, which asks the reader to trust the claim. Here
//  the lock is the platform's own Sendable primitive and the state is a value
//  the class never exposes except through `withLock`, so the compiler checks
//  the claim: `OSAllocatedUnfairLock` on Apple platforms, `Synchronization.Mutex`
//  elsewhere (`Mutex` itself needs macOS 15 / iOS 18, above this package's floor).
//

#if canImport(os)
import os

final class LockedState<State: Sendable>: Sendable {
    private let lock: OSAllocatedUnfairLock<State>

    init(_ initialState: State) {
        lock = OSAllocatedUnfairLock(initialState: initialState)
    }

    func withLock<Result: Sendable>(_ body: @Sendable (inout State) -> Result) -> Result {
        lock.withLock(body)
    }
}
#else
import Synchronization

final class LockedState<State: Sendable>: Sendable {
    private let mutex: Mutex<State>

    init(_ initialState: State) {
        mutex = Mutex(initialState)
    }

    func withLock<Result: Sendable>(_ body: @Sendable (inout State) -> Result) -> Result {
        mutex.withLock { body(&$0) }
    }
}
#endif
