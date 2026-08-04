import SwiftQL

// The example schema for the Getting Started playground.
//
// These declarations live here, in a compiled package target, rather than in
// the playground itself. Classic Xcode playgrounds have no `Package.swift` of
// their own and no reliable way to load a Swift macro compiler plugin, so a
// playground page cannot expand `@SQLTable`. Declaring the tables here means
// the macro runs during the ordinary package build and the playground only
// ever consumes already-expanded, already-compiled API.

/// A person, the primary table used throughout the Getting Started material.
///
/// The property types mirror the ones documented in the Getting Started guide:
/// `String` maps to SQLite `TEXT`, `Int` to `INTEGER`, and an optional
/// property is the one column allowed to hold `NULL`.
@SQLTable
public struct Person {
    public var id: String
    public var occupationId: String?
    public var name: String
    public var age: Int
}

/// An occupation a person can hold.
///
/// The playground uses this second table for the joins and lookups that need
/// more than one table in scope.
@SQLTable
public struct Occupation {
    public var id: String
    public var title: String
}
