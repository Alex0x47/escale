# Escale

<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="Escale app icon">
</p>

<p align="center">
  <strong>Ship iOS and Android apps from one native macOS workspace.</strong>
</p>

<p align="center">
  Manage App Store Connect and Google Play listings, screenshots, releases,
  pricing, products, and reviews without living in two browser consoles.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Mac-Apple%20silicon-555555">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138">
  <img alt="Apache-2.0" src="https://img.shields.io/badge/license-Apache--2.0-blue">
</p>

<p align="center">
  <a href="https://www.useescale.com/">Website</a> ·
  <a href="https://www.useescale.com/download">Download Escale</a> ·
  <a href="#community-or-pro">Compare editions</a> ·
  <a href="https://litefeedback.com/roadmap/Escale">Feedback and roadmap</a>
</p>

Escale connects directly to the official Apple and Google APIs. Credentials stay
in macOS Keychain, fetched workspace data is cached locally, and remote changes
remain explicit: you review the work before Escale writes it to a store.

## What you can do

- Link matching iOS and Android apps in one workspace.
- Edit localized store listings while keeping each platform's copy separate.
- Translate a complete listing or one field with your own OpenAI API key.
- Generate correctly tagged Google Play release notes.
- Upload, inspect, and remove screenshots for both stores.
- Create editable App Store versions without submitting them for review.
- Read in-app products and subscriptions from Apple and Google.
- Calculate store-valid regional prices using Worldwide PPP, Netflix, or Big Mac
  indices.
- Read customer reviews and publish developer replies.
- Follow progress and partial failures during long-running store operations.

Demo mode is clearly identified and never writes to a remote store.

## Community or Pro?

**Escale Community** is the application in this repository. It is free,
open-source under Apache-2.0, and provides a complete manual workflow with no
trial deadline: one developer account per store, unlimited linked apps, manual
listing and screenshot management, customer-review replies, single-locale
translation, and PPP price calculation and preview.

> [!TIP]
> **Spend less time repeating store work with [Escale Pro](https://www.useescale.com/download).**
>
> Pro includes everything in Community, then adds bulk translation across every
> locale, one-click regional price application, reusable What's New templates,
> AI-generated customer-review reply drafts, and Google Play bundle upload with
> editable draft-release creation.
>
> Escale Pro is currently **$99/year for one user on up to two Macs** and includes
> current and future Pro features while the subscription is active.
> [Explore Escale Pro →](https://www.useescale.com/download)

| Capability | Community | Pro |
| --- | --- | --- |
| Store listing and screenshot management | Manual | Manual |
| Customer-review replies | Write and publish manually | Manual replies plus AI-generated drafts |
| Linked applications | Unlimited | Unlimited |
| Developer accounts | One per store | One per store |
| App Store version creation | Included | Included |
| Google Play bundle upload and draft creation | — | Included |
| AI-assisted translation | One locale at a time | Every app locale |
| What's New templates | — | Included |
| PPP regional pricing | Calculate and preview | Apply to both stores |
| Synchronization | Manual | Manual |

AI review-reply drafting requires Escale Pro. Both editions can still write,
edit, and publish customer-review replies manually.

The Community source and reusable `EscaleCore` and `EscaleUI` libraries remain
Apache-2.0 licensed. Escale Pro is a separate commercial distribution with
proprietary licensing and implementation. See
[the edition architecture](Documentation/EDITIONS.md) for the technical boundary.

## Before using a production account

> [!CAUTION]
> **Escale can make consequential remote changes. Review them in Escale and
> verify important results in the official store console.**

Escale can remotely change public metadata, screenshots, prices, subscriber
price behavior, releases, and review replies. Apple or Google API changes,
incorrect permissions, defects, or user error can cause production impact.
Use least-privilege credentials, keep copies of important metadata, and start
with a non-critical app. There is no automatic rollback.

The software is provided without warranty. See the
[Apache-2.0 licence](LICENSE), especially its warranty and liability terms.

## Requirements

- Apple silicon Mac (M1 or newer)
- macOS 14 or newer
- Xcode 16 or newer with the Command Line Tools
- Swift 6
- [ImageMagick](https://imagemagick.org/) for building the `.app` bundle
- An App Store Connect and/or Google Play Console account
- An OpenAI API key only for AI-assisted features

There are no third-party Swift package dependencies.

## Run from source

```bash
git clone git@github.com:Alex0x47/escale.git
cd escale
brew install imagemagick
./scripts/install-git-hooks.sh
./scripts/run-app.sh
```

The run script builds `dist/Escale.app`, creates its icon, signs it with the
first available Apple Development identity, and opens it. If no development
identity is available, it uses an ad-hoc signature; macOS may then ask for
Keychain access again after a rebuild.

To select a signing identity:

```bash
ESCALE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" \
./scripts/run-app.sh
```

For quick UI work that does not need persistent Keychain access:

```bash
swift run Escale
```

To create an optimized standalone bundle:

```bash
./scripts/build-app.sh
open dist/Escale.app
```

Distributing a trusted build to other Macs requires your own Developer ID
certificate, hardened-runtime configuration, and Apple notarization.

## Connect your stores

### App Store Connect

Create a Team API key under **Users and Access → Integrations**, then add its
Issuer ID, Key ID, and `.p8` file in Escale. App Manager access is the usual
starting point; grant only the access your workflows need.

[Apple's App Store Connect API setup guide](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)

### Google Play

Enable the Google Play Android Developer API, create a Google Cloud service
account, invite its email under **Play Console → Users and permissions**, and
grant access only to the required apps and features. Add the exact Android
package names in Escale because the publishing API cannot enumerate every app
in an account.

[Google's Android Publisher API setup guide](https://developers.google.com/android-publisher/getting_started)

### Optional AI features

Add your own [OpenAI API key](https://platform.openai.com/api-keys) in Escale
Settings. Requests go directly from the Mac to OpenAI, and usage is billed to
the account that owns the key. Always review generated translations and reply
drafts before publishing them.

## Local data and security

| Data | Storage |
| --- | --- |
| Apple API credentials | macOS Keychain |
| Google service-account document | macOS Keychain |
| OpenAI API key | macOS Keychain |
| OAuth access tokens | Process memory only |
| Imported data and pending edits | Local workspace cache |
| Generated Google Play release notes | Local workspace cache |

Disconnecting a store removes its credential from Keychain. Escale is
local-first, but connected workflows necessarily send requests to Apple,
Google, public pricing-data sources, and—when you invoke an AI action—OpenAI.
Never commit credentials or include real secrets in issues, screenshots, or
logs.

## Development

```text
Sources/
├── EscaleCore/                   # Models, APIs, security, persistence, orchestration
├── EscaleUI/                     # Reusable SwiftUI screens and app shell
└── EscaleCommunityApp/           # Community executable and resources

Tests/EscaleCoreTests/             # Domain, decoding, crypto, and smoke tests
scripts/run-app.sh                 # Recommended local development launch
scripts/build-app.sh               # Standalone app-bundle assembly
```

Run the test suite with:

```bash
swift test
```

The default tests do not change store data. Optional live smoke tests run only
when their documented environment variables are supplied in the test code.

Escale's semantic version is stored in [`VERSION`](VERSION). The tracked
pre-commit hook increments its patch version on each commit, so install the hook
once per clone with `./scripts/install-git-hooks.sh`.

## Contributing

Contributions are welcome, particularly reproducible API fixes, store-response
fixtures, safer validation and confirmation flows, accessibility improvements,
tests, and documentation corrections.

1. Fork the repository and create a focused branch.
2. Make the change without adding credentials or production data.
3. Add or update tests where appropriate.
4. Run `swift test`.
5. Open a pull request describing the affected remote behavior and verification.

Use the [feedback board](https://litefeedback.com/roadmap/Escale) for feature
ideas. If a credential may have leaked, revoke it immediately and do not post it
in a public issue.

## Licence

Escale Community is licensed under the
[Apache License 2.0](LICENSE) (`Apache-2.0`). You may use, inspect, modify, and
redistribute it, including in proprietary products, subject to the licence
terms. Required licence and attribution notices must be retained, and modified
files must carry prominent change notices. The licence includes an express
patent grant but does not grant rights to the Escale name or trademarks.

Copyright © 2026 Alexandre Grisey and Escale contributors.

Escale is independent and is not affiliated with, endorsed by, or sponsored by
Apple, Google, OpenAI, Netflix, The Economist, or the World Bank. Their product
names and trademarks belong to their respective owners.
