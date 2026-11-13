# Mickey's Apple TV app, for personal builds

[mickey2266/AIOStreamsTVOS](https://github.com/mickey2266/AIOStreamsTVOS) has no licence, and its
README says builds are for personal use. So this folder holds none of its code: only the commit to
build (`MICKEY_REF`) and our own changes to it (`patches/*.patch`, applied in name order). The
**Build Apple TV (personal)** workflow clones that commit, applies the patches, builds the app the
way its own workflow does, and attaches the IPA to the run. It publishes no release and no
sideloading source.

- **His updates:** put a newer commit in `MICKEY_REF`. A patch that no longer applies stops the
  build and is named.
- **Our changes:** a `git diff` made inside a checkout of his repo, saved as
  `patches/NN-what.patch`.
- **Installing over his app:** the build number is 100000 plus the run number, so tvOS takes it as
  an update to his app (same bundle identifier). Going back to his builds means deleting this one first.
