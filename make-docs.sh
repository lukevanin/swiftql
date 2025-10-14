#!/bin/sh

set -e

# See https://swiftlang.github.io/swift-docc-plugin/documentation/swiftdoccplugin/publishing-to-github-pages

swift package --allow-writing-to-directory ./docs \
    generate-documentation --target SwiftQL \
    --disable-indexing \
    --transform-for-static-hosting \
    --hosting-base-path swiftql \
    --output-path ./docs
    
touch docs/.nojekyll

git add --all .

git commit -m "Update documentation."
