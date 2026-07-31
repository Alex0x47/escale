# Maintaining Community and the official distribution

This repository is the source of truth for Escale Community only. The official
signed distribution consumes a reviewed, immutable Community revision and adds
its own distribution services and commercial workflows outside this repository.

## Repository boundaries

```text
Public Escale repository
├── EscaleCore
├── EscaleUI
└── EscaleCommunityApp

Private Escale commercial repository
├── dependency: public Escale package at a pinned revision
├── distribution and licence services
├── commercial workflow implementations
└── EscaleProApp
```

For local development, the private package may live beside this repository at
`../escale-pro`. Release builds must use an immutable tag or commit revision so
a later Community change cannot alter an already-reviewed distribution.

The private package should import the public library products:

```swift
.product(name: "EscaleCore", package: "escale"),
.product(name: "EscaleUI", package: "escale")
```

During local development, the private repository can use a local path dependency. Release builds should use an immutable tag or commit revision so a community update cannot change the commercial build unexpectedly.

## Fixing a bug in both editions

1. Reproduce the bug against the public shared package.
2. Fix it in `EscaleCore` or `EscaleUI`.
3. Add or update the public regression test.
4. Release a public tag or record the tested commit.
5. Update the private repository's dependency pin.
6. Run the commercial test and signing pipeline.

Commercial source never passes through the public repository.

If a bug exists only in a commercial feature, fix it in `EscaleProKit`. If a commercial feature reveals a defect in shared behavior, keep the general fix public and the commercial integration private.

## Adding features

Community features belong in `EscaleCore` and `EscaleUI`. Commercial-only
features belong in the private distribution repository. Public protocols should
be general Community extension points, not hooks whose only purpose is to expose
locked commercial controls.

Avoid conditional compilation such as `#if PRO` in shared files. It makes accidental feature leakage easier and leaves the community build responsible for code it cannot test. Keep edition-specific implementations in edition-specific targets and repositories.

## Licensing boundary

The public Escale package is licensed under Apache-2.0. Selling the official
signed distribution does not make incorporated Community code proprietary or
remove recipients' Apache-2.0 rights. The subscription pays for signing,
notarization, licence management, signed updates, support, release operations,
and convenience.

The commercial distribution must include a copy of the Apache-2.0 licence, retain applicable copyright and attribution notices, mark modified public files, and reproduce any `NOTICE` file if one is added later. Apache-2.0 does not grant rights to the Escale name or trademarks.

Contributions intentionally submitted to this repository are licensed under
Apache-2.0 by default under section 5 of the licence. This is a project-design
summary rather than legal advice.

## Repository locations

- Public Community repository: `https://github.com/Alex0x47/escale.git`
- Private commercial repository: `git@github.com:Alex0x47/escale-pro.git`

Keep the public repository configured as the private package dependency. Do not
add the private repository as a submodule, subtree, or remote of the public
repository: that would weaken the one-way boundary and make accidental
publication easier.
