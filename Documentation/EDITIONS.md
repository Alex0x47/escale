# Maintaining community and commercial editions

Escale uses a shared-package architecture. The community repository is the source of truth for every capability shipped in both editions; the commercial repository contains only commercial additions and its executable shell.

## Repository boundaries

```text
Public Escale repository
├── EscaleCore
├── EscaleUI
└── EscaleCommunityApp

Private Escale commercial repository
├── dependency: public Escale package at a pinned revision
├── EscaleProKit
└── EscaleProApp
```

For local development, the private package lives beside this repository at
`../escale-pro`. Its `EscaleProEntitlements` provider starts in Community mode
and is unlocked only by the private licence manager.

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

No cherry-pick is needed, and commercial source never passes through the public repository.

If a bug exists only in a commercial feature, fix it in `EscaleProKit`. If a commercial feature reveals a defect in shared behavior, keep the general fix public and the commercial integration private.

## Adding features

Shared features belong in `EscaleCore` and `EscaleUI`. Commercial-only features belong in `EscaleProKit`. The public UI exposes the root view, settings, sidebar, and current feature screens so the commercial app can compose shared screens without copying them.

Avoid conditional compilation such as `#if PRO` in shared files. It makes accidental feature leakage easier and leaves the community build responsible for code it cannot test. Keep edition-specific implementations in edition-specific targets and repositories.

`EscaleUI` exposes an optional `EscaleCommercialActions` environment value.
The Community executable leaves it unset. A commercial executable can use it
to open its private purchase and licence-management UI from shared feature
gates and Settings without placing payment or licence code in the public
package.

## Licensing boundary

The public Escale package is licensed under Apache-2.0. The private commercial product may incorporate and modify `EscaleCore` and `EscaleUI` while keeping `EscaleProKit` and the rest of the commercial application proprietary, provided the Apache licence conditions are followed.

The commercial distribution must include a copy of the Apache-2.0 licence, retain applicable copyright and attribution notices, mark modified public files, and reproduce any `NOTICE` file if one is added later. Apache-2.0 does not grant rights to the Escale name or trademarks.

Contributions intentionally submitted to this repository are licensed under Apache-2.0 by default under section 5 of the licence. A separate contributor agreement is therefore not required merely to consume those contributions in an Apache-compliant proprietary distribution, although one may still be useful for broader relicensing or intellectual-property assurances. This is a project-design summary rather than legal advice; have the final distribution and contributor process reviewed professionally.

## Repository locations

- Public Community repository: `git@github.com:Alex0x47/escale.git`
- Private commercial repository: `git@github.com:Alex0x47/escale-pro.git`

Keep the public repository configured as the private package dependency. Do not
add the private repository as a submodule, subtree, or remote of the public
repository: that would weaken the one-way boundary and make accidental
publication easier.
