// This target exists to run SwiftQL's build-time query validation over the
// demo's declared queries. It holds no code: the two files beside this one —
// the checked-in schema snapshot and the query manifest describing it — are
// the target's real contents, and the plugin attached to it in Package.swift
// prepares every query in the manifest against that snapshot on every build.
//
// It is a separate target from TodoKit, rather than a plugin attached to
// TodoKit itself, for a historical reason. The plugin resolves the validator
// through `context.tool(named:)`, which names the executable *target*, while
// Xcode builds a package executable under its *product* name. Before v1.5.6
// the two names differed, so any target carrying the plugin failed to build
// from an Xcode project with "Build input file cannot be found". Keeping the
// plugin on a target the app does not link avoided that.
//
// That bug, issue #492, was fixed in v1.5.6 by giving the executable target
// the product's name, `swiftql-build-validate`, so this target could now be
// folded back into TodoKit: move the three files beside TodoDatabase.swift,
// attach the plugin to TodoKit, and delete this file. That move has not been
// made yet.
enum TodoKitBuildValidation {}
