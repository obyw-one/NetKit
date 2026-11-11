//
//  LockedState.swift
//  NetKit
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
