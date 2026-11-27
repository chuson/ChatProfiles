# Releasing

1. Set `## Version` in `ChatProfiles/ChatProfiles.toc` (for example `0.2.0`) and commit it.
2. Tag that commit with the same version and push the tag: `git tag v0.2.0` then `git push origin v0.2.0`. A suffix like `v0.2.0-beta1` makes a pre-release.

Each version is released exactly once. The release workflow stops if the tag isn't shaped like `v1.2.3`, doesn't match the `.toc`, or is already released, and the Checks workflow warns when the addon changes after its version was released. Released tags can't be deleted or moved (a GitHub tag ruleset on `v*`).

After those checks, the release workflow runs luacheck and the tests, and publishes `ChatProfiles-v0.2.0.zip` (the addon folder with `LICENSE`) and a `release.json` to GitHub Releases. Addon managers such as WowUp install and update from there.
