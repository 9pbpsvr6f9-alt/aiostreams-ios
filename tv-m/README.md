# tv-m: the Apple TV app, for personal builds

The upstream Apple TV app (the repository in `UPSTREAM`) has no licence, and its README says builds
are for personal use. So this folder holds none of its code, only:

- `UPSTREAM` and `UPSTREAM_REF`: where the app comes from and the commit to build.
- `AIOSTREAMS_REF`: the AIOStreams commit for its web app, as the upstream web patches only fit some.
- `patches/*.patch`: our own changes, applied in name order.

The **Build tv-m** workflow clones that commit, applies the patches, builds the app the way the
upstream workflow does, and attaches `tv-m.ipa` to the run. It publishes no release and no
sideloading source.

- **Upstream updates:** put a newer commit in `UPSTREAM_REF`, and in `AIOSTREAMS_REF` the newest
  AIOStreams commit the upstream `patches/web` apply to, in order. A patch that no longer applies stops
  the build and is named.
- **Our changes:** a `git diff` made inside a checkout of the upstream app, saved as
  `patches/NN-what.patch`.
- **Installing over the upstream app:** the build number is 100000 plus the run number, so tvOS takes
  it as an update (same bundle identifier). Going back means deleting this build first.
