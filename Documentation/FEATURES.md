# Escale Community scope

This repository contains the complete Escale Community application. It must not
contain commercial workflow implementations hidden behind entitlement checks,
lock buttons, conditional compilation, or an alternate executable.

## Community

- Manual listing management
- Manual screenshot management
- Manual review management and replies
- One App Store Connect developer account
- One Google Play developer account
- Unlimited linked applications
- Manual synchronization
- PPP price calculation and preview for one selected product at a time
- Translation of a full listing or individual field into one selected locale
- Creation of editable App Store versions

The Community implementation ends at those boundaries. In particular, it does
not include bulk locale operations, remote regional-price application, reusable
release-note templates, AI review drafting, or Google Play bundle/release
creation. The interface presents Community actions directly and does not show
disabled commercial controls.

The official signed distribution may advertise additional maintained workflows,
but their implementation belongs outside this public source tree. Shared fixes
should be extracted to a genuinely Community-usable API before they are added
here. Planned ideas must not be presented as shipped features.
