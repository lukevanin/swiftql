# Sourced, not executed: the one place that pins Hugo for the documentation
# site (#611).
#
# make-docs.sh accepts only this Hugo version, because check-blog-output.sh
# asserts on output that changes between Hugo releases. install-hugo.sh installs
# exactly this release, and refuses the download unless it matches the SHA-256
# below, which is the digest GitHub records for the release asset.
#
# To move the pin, change both values in one commit, and confirm that
# check-blog-output.sh still passes on the new release's output.

SWIFTQL_HUGO_VERSION=0.165.0

# hugo_extended_withdeploy_0.165.0_darwin-universal.pkg: the same edition as
# Homebrew's hugo formula, which CI installed before #611.
SWIFTQL_HUGO_DARWIN_UNIVERSAL_SHA256=d00e3966136c4f369e4b9601a461826d16076cd28ecf4a7b0a2815e6ed09531d
