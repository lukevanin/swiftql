// This target exists to run SwiftQL's build-time query validation over the
// demo's declared queries. It holds no code: the two files beside this one —
// the checked-in schema snapshot and the query manifest describing it — are
// the target's real contents, and the plugin attached to it in Package.swift
// prepares every query in the manifest against that snapshot on every build.
//
// It is a separate target from TodoKit, rather than a plugin attached to
// TodoKit itself, because of a SwiftQL limitation: the plugin resolves the
// validator through `context.tool(named: "SwiftQLSQLiteBuildValidationValidatorCLI")`,
// which is the executable *target* name. SwiftPM builds that artifact under
// its target name, but Xcode builds it under the executable *product* name
// (`swiftql-build-validate`), so any target carrying the plugin fails to
// build from an Xcode project with:
//
//     error: Build input file cannot be found:
//     '.../Build/Products/Debug/SwiftQLSQLiteBuildValidationValidatorCLI'
//
// Keeping the plugin on a target the app does not link means `swift build`
// and `swift test` still run validation on every build, while the Xcode app
// target — which never pulls this target into its graph — builds cleanly.
//
// The underlying bug is issue #492, fixed by PR #501, which renames the
// executable target to match its product. Once that lands, fold this target
// back into TodoKit: move the two artifacts beside TodoDatabase.swift, attach
// the plugin to TodoKit, and delete this file.
enum TodoKitBuildValidation {}
