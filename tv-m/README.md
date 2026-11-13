# tv-m: the Apple TV app, for personal builds

The upstream Apple TV app (the repository in `UPSTREAM`) has no licence, and its README says builds
are for personal use. So this folder holds none of its code, only:

- `UPSTREAM` and `UPSTREAM_REF`: where the app comes from and the commit to build.
- `AIOSTREAMS_REF`: the AIOStreams commit for its web app, as the upstream web patches only fit some.
- `patches/*.patch`: our own changes to the app, applied in name order.
- `web/*.patch`: our own changes to its web app, added to the upstream web patches and applied
  after them by name: `0100` the skip countdown, `0101` the spoiler blur, `0102` Liquid Glass, `0103` the launch
  logo's place for the app (with `patches/0001`, which draws it from the first frame), `0104` the
  countdown's setting, Back to keep watching, a larger skip button, glass focus on text, the
  glass floating rail and its Hide the rail while browsing switch. `0105` sends a poster with each
  Top Shelf item, which `patches/0002` shows in the shelf's poster shape. `0106` puts Who's watching in glass. `0107` adds Settings > Account > Ask every time you come
  back, kept on the device.

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
