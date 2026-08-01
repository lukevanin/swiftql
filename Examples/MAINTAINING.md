# Maintaining the Getting Started playground

The playground is documentation that runs, which means it can break in ways
prose cannot. This is what to do when it does, and what to re-check when the
things it mirrors change.

## The check

```sh
scripts/ci/check-playground-pages.sh [OUTPUT_DIRECTORY]
```

It does three things:

1. Builds `SwiftQLExamples`, the companion module the pages import.
2. Compares `contents.xcplayground` against the `Pages` directory, so a page
   added to one and not the other fails rather than silently disappearing from
   the navigator.
3. Copies each page's `Contents.swift` to `main.swift` in a throwaway SwiftPM
   package that depends on this checkout, builds it, and runs it. A page that
   fails to compile, compiles with a warning, exits non-zero, or does not
   finish within `SWIFTQL_PLAYGROUND_PAGE_TIMEOUT` seconds (180 by default)
   fails the check.

A page's top-level code is exactly what an executable target's `main.swift`
holds, so pages run unmodified. Passing an output directory writes
`page-output.txt` and `summary.md`.

CI runs this in `swift.yml`'s `compatibility` job, on the one cell gated to
macOS with committed resolution: Swift 6.0 on macos-15. The clean-resolution
macOS cell does not run it, and neither do the Linux cells. That run passes an
output directory and uploads it as an artifact, so the per-page transcript
survives a failure. What it does not cover is Xcode's own playground runner
and its results sidebar, which are not scriptable. Opening the workspace and
stepping through the pages is still worth doing before a release.

## When the Getting Started guide changes

The playground mirrors
[GettingStarted.md](../Sources/SwiftQL/SwiftQL.docc/GettingStarted.md)'s arc
and terminology, and the live-queries page mirrors
[LiveQueries.md](../Sources/SwiftQL/SwiftQL.docc/LiveQueries.md). Neither is
generated from the other, so a change to the guide does not change the
playground by itself.

When you change the guide:

1. Find the page covering that material. `Examples/README.md` has the page
   table.
2. Update the page's markup to match the guide's wording. Terminology matters
   more than phrasing; a reader moving between the two should not have to work
   out that "invocation packet" and "bindings packet" are the same thing.
3. Update the runnable code, and update the expected output stated next to it.
4. Run the check.

When you add a section to the guide that deserves its own page, add the page
directory under `Pages`, add a `<page name='...'/>` entry to
`contents.xcplayground` in the right position, fix the `@previous` and `@next`
links on either side of it, and add a row to the table in
`Examples/README.md`. The check enforces the first two of those; the links and
the table are on you.

## When the example schema changes

`Person` and `Occupation` in
`Examples/Sources/SwiftQLExamples/ExampleSchema.swift` are load-bearing for
every page. Adding a column changes every `Person(...)` call in the pages and
every printed row. Renaming one changes the queries too.

`ExampleDatabase.seedPeople` and `ExampleDatabase.seedOccupations` are what
pages calling `makeSeeded()` start from, so changing a seed row changes the
documented output of most pages. Prefer adding a row over editing one, and
check the pages that print counts (`5 Delete statements`, `8 Transactions`)
either way.

## When SwiftQL's API changes

The compiler catches the parts of this that are code. `SwiftQLExamples` is a
first-party target, so `swift build`, `swift build --build-tests`, and the
warnings-as-errors gate all compile it, and a renamed or removed API breaks
the build the same way it would break any other target.

What the compiler does not catch:

- **Prose that has gone stale.** A page can compile perfectly and still
  describe behaviour that changed. The rules quoted on pages 7 and 9 come from
  `GettingStarted.md` and `LiveQueries.md`; when those articles change their
  guarantees, search the pages for the affected wording.
- **Output that has drifted.** Every page states its expected output in a
  markup comment. The check runs the pages but does not compare their output
  against those comments, because the comparison would be a second copy of the
  expected output with its own drift problem. Read the check's printed output
  when you change a page.
- **A new API worth teaching.** Nothing prompts you to add a page. Adding one
  is a judgement call at the point the API ships, not a maintenance task.

Two constraints the pages work around are recorded in `Examples/README.md`:
live queries deliver on the main queue, and nullable columns cannot be
assigned in a `Setting` closure. If either is fixed, the workaround and the
note explaining it should go.
