# Cutting a patch release

A patch fixes the host side of a series that people already build against.
The compiler, the SDK, the client: anything that runs on the developer's
machine. What it does not do is move the target runtime — newlib, the vita
headers, pthread-embedded — because a binary built against 2026.08.0 has to
keep meaning the same thing after 2026.08.1. A release that swapped those
would not be a patch, whatever it is called.

That single rule is what shapes every step below, and it is why a patch
branches from `master` rather than from the release it patches: the host-side
fixes are already there, and it is the *target* pins that go back.

The worked example is 2026.08.1, cut on 2026-08-25. It exists because the
cores that 2026.08.0 published refused to start on anything older than glibc
2.38, so the SDK was rebuilt on the glibc floor the published cores use now,
with the same target sources.

## 1. Branch and declare the version

```sh
git switch -c next-patch-2026.08.1 master
echo 2026.08.1 > VERSION
```

`VERSION` is the whole mechanism. `buildscripts-ci describe` reads it at the
revision it is describing, and a lock built from a tree that carries one says
so twice: `version` is the string in the file, and `series` is everything up
to the last dot. A tree without the file derives its version from history and
has no series at all, which is what a nightly is.

Both fields end up in the `lock.json` published inside the core release, and
that is what the rest of the chain reads.

## 2. Roll the target back to what the series shipped

In `cmake/Components.cmake`, put the three target components back to the
revisions that series published, and leave everything else alone. For
2026.08.1 that was newlib `6cba9812`, vita-headers `ebc8f4f7` and
pthread-embedded `610934f4` — master was 2445 newlib commits and a major
version ahead. gcc, binutils, gdb, the host libraries, vita-toolchain and the
samples were identical between the two, and vdpm and vita-makepkg stayed
current, since the host side is what the release exists to fix.

Look at what the series actually shipped rather than at what the tag says:

```sh
gh release download <the series' core tag> --repo vitasdk/autobuilds \
    --pattern lock.json --output - | jq .sources
```

## 3. The fixes

Ordinary commits. Two things worth knowing before they turn red:

* Infrastructure written since the series was cut has never been pointed at
  these sources. 2026.08.1 hit exactly that: `check-toolchain-contract`
  compiles every public header on its own, and two headers the series had
  always shipped do not compile that way. That is not a reason to skip the
  check — it is what a patch is for.
* A fix that has to land in a component takes the same shape there: a branch
  off the revision the series pinned, not off the component's development
  branch, and then the pin moves to it.

## 4. Build it

Dispatch **Build SDK snapshots** in `vitasdk/autobuilds` with
`buildscripts_ref` set to the branch. It describes the tree, builds every host
in the lock, publishes `sdk-snapshot-<date>.<run>.<attempt>` with `lock.json`
inside it, and announces the tag to the package autobuilder along with the
series it belongs to.

Required hosts are release policy and live in that workflow: if one of them
cannot build at this revision, nothing publishes.

## 5. The catalogue

`vitasdk/vitasdk-autobuild` answers the announcement, builds the packages
against that exact core and publishes `packages-<series>-snapshot-...` with a
`provenance.json` naming the core it was built against. A series' catalogue is
separate from nightly's on purpose: same recipes, different core.

## 6. Point the series at it

Run **Update Channel Manifest** in `vitasdk/autobuilds` with the core tag, the
packages tag, and the channel set to the series name (`2026.08`, not
`nightly`). It refuses the pair unless:

* both releases exist and publish the files it needs;
* the packages record that exact core as the one they were built against;
* the core's lock declares the series being published — and `nightly` takes
  only cores that declare none.

Then it signs the manifest, pushes it to the Pages site, waits until the
signed file is actually being served, and tells the image builder the series
moved.

## 7. Tag it

```sh
git tag vitasdk-2026.08.1 <the revision that was built>
git push origin vitasdk-2026.08.1
```

The tag is a name for a revision people can go back to. What identifies the
release everywhere else is the lock: version, series, buildscripts revision
and the exact source of every component.

## What went wrong the first time

Both blockages came from the same place — a release branch is the one tree
that does not derive its version, and nothing had ever been one.

**The CI of the tag went red on tests, not on builds.** All thirteen build
jobs passed; two protocol tests failed because they assume the repository
derives its version. The monotonicity test walks first-parent history
asserting each version precedes the next, and on a release branch every commit
answers with the same declared string. Fixed in `a75f24689`: a declared
version is now a reason to skip that walk, the way a collapsed PR merge range
already was — which also un-skipped the checks below it, the ones that are
about declared versions.

**The publisher had no way to know which series it was publishing.** The lock
did not carry it, so every core was announced the same way, and an
announcement with no series names the unnamed one: nightly. Publishing
2026.08.1 that way would have moved every nightly user onto the target runtime
of a series they are not on. Fixed in `79a927840` by deriving the series where
the version is known, and closed at the other end by the pair check in step 6.

**And one hole found while looking:** `--previous-version` skipped a committed
`VERSION` outright, so the guard that stops a version going backwards covered
only the derived path — the one where it cannot happen by accident — and not
the one where a person types the number. Closed in `287d8a8f4`. Nothing passes
`--previous-version` in production yet.
