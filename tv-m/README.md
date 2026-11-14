# tv-m: the Apple TV app, for personal builds

The upstream Apple TV app (the repository in `UPSTREAM`) has no licence, and its README says builds
are for personal use. So this folder holds none of its code, only:

- `UPSTREAM` and `UPSTREAM_REF`: where the app comes from and the commit to build.
- `AIOSTREAMS_REF`: the AIOStreams commit for its web app, as the upstream web patches only fit some.
- `patches/*.patch`: our own changes to the app, applied in name order. `0001` the launch logo, `0002` Top
  Shelf posters in one row, `0003` frosted glass behind the search keyboard in place of black.
- `web/*.patch`: our own changes to its web app, added to the upstream web patches and applied
  after them by name: `0100` the skip countdown, `0101` the spoiler blur, `0102` Liquid Glass, `0103` the launch
  logo's place for the app (with `patches/0001`, which draws it from the first frame), `0104` the
  countdown's setting, Back to keep watching, a larger skip button, glass focus on text, the
  glass floating rail and its Hide the rail while browsing switch. `0105` sends a poster with each
  Top Shelf item, which `patches/0002` shows in the shelf's poster shape. `0106` puts Who's watching in glass. `0107` adds Settings > Account > Ask every time you come
  back, kept on the device. `0108`: Settings > Interface > Background (a frosted backdrop
  following the hero or the highlighted card), Who's watching on a frosted aurora with thinner
  rings, a smaller skip button, Down selecting Keep watching during a countdown. `0109` draws that background without
  filters, which the app turns off: a tiny, box-blurred copy of the picture, stretched and dimmed,
  and a tall plain fade from the hero into it. `0110` puts Who's watching up as the app goes away, so a return
  opens on it. `0111` draws the floating top tabs as glass.
  `0112` marks the current tab with a dot in place of a capsule, takes the hero to the left edge
  and fades its bottom into the frosted background, keeps the watch party sheet's shape, and draws
  a row title's focus pill inside its box.
  `0113` draws the top tabs as tvOS does (a solid white focused tab, a grey capsule for the page
  you're on), calms the glass, thins the focus ring, fits a row title's pill in its own box, and
  shortens the hero so the first row peeks in. `0003` also fades the search keyboard's frost out above
  the results.
  `0114` takes title, collection and follow-hero backdrops to the left edge too, and fades a title's
  backdrop into the frosted background as Home's hero does.
  `0115` has the frosted background soften a title's or collection's own picture on its page, so a
  collection with no backdrop is one blurred copy of its picture, edge to edge.
  `0116` adds the air time beside the day on Upcoming's cards, where the listing gives one.
  `0117` makes the hero taller again (84% of the screen), closes the line under it, and keeps Home's
  background on the hero's picture while the hero is on screen.
  `0118` lays Search out as tvOS does: the keyboard at the top as the only field, results just below,
  the term in a glass pill once the keyboard closes, and no second list of suggestions. The background
  follows the highlighted result there, and pages with nothing to follow stay plain. Native `0004`
  marks the page while the keyboard is up, for this.
  `0119` draws the art's fade into the background on one canvas, in a smooth ramp with no seams, and
  puts it on as soon as the art appears.
  `0120` decodes each background picture before it shows and draws the fade before the first frame,
  so the fade changes in step with the background.
  `0121` fixes 0120, which declared a name twice and stopped the app at its logo, loads the picture
  by its load event with a short cap, and keeps the background in an error boundary so it can never
  stop the app again.
  `0122` starts a new background picture, and its fade over the art, only once the picture has
  loaded, so the two crossfade together.
  `0123` joins Home's hero to the rows through one fixed grey, the hero fading into it and the rows
  out of it, so the edge never changes with the background.
  `0124` starts the rows' grey two pixels over the hero's edge, so no background shows between them.
  `0125` brings Liquid Glass to what was still flat: rows of pills as separate glass pills, the
  catalog and filter pickers and row buttons as glass capsules, frosted date pills, and a collection's
  picture standing in for its name.
  `0126` centres a collection's picture and fades its edges into the background, shows a
  collection's posters as large as Home's and opens it at the top, has Discover's background follow the
  highlighted card, and puts a soft aurora behind Search, whose keyboard (`0003`) now has a lighter frost.
  `0127` picks the background by the page that's open (Home stays mounted under the others, so its
  hero was always found), opens a collection with its first row in view, and makes Search's field
  wider glass that brightens under the remote instead of turning white.

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
