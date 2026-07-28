# Escale

<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="Escale app icon">
</p>

<p align="center">
  A local-first native macOS workspace for managing App Store Connect and Google Play.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138">
  <img alt="Apache-2.0" src="https://img.shields.io/badge/license-Apache--2.0-blue">
</p>

> [!CAUTION]
> **Escale is experimental software under active development. Use it entirely at your own risk.**
>
> Escale connects to live production accounts and can remotely modify store listings, screenshots, in-app product and subscription pricing, subscriber price behavior, localizations, and public review replies. A defect, API change, incorrect permission, misunderstood option, or user error may cause financial loss, rejected releases, unintended review submissions, incorrect prices, lost metadata, or other production impact.
>
> Always verify proposed changes in App Store Connect and Google Play Console, keep independent copies of important metadata, use least-privilege credentials, and test with non-critical apps and products first. You are solely responsible for every credential supplied and every remote operation performed with this software.
>
> Escale is provided **without warranty of any kind**. To the maximum extent permitted by applicable law, its authors and contributors are not liable for damages or losses arising from its use. See the [Apache-2.0 licence](LICENSE), particularly its warranty and liability provisions.

## Project status

Escale started as an experiment in building a useful native developer tool with AI-assisted development. It is now open source so that its behavior can be inspected, tested, improved, and adapted by the community.

It is not a finished or audited production product:

- Apple and Google can change their APIs and review behavior without notice.
- Not every account configuration, product state, locale, territory, or historical pricing schedule has been tested.
- A successful API response does not replace checking the resulting state in the official store console.
- There is currently no stable-release compatibility promise.

Review the code paths relevant to your workflow before granting access to valuable production accounts.

## What Escale does

- Connects directly to App Store Connect using an Issuer ID, Key ID, and `.p8` Team API key.
- Connects directly to Google Play using a Google Cloud service-account JSON document.
- Imports live apps and pairs iOS and Android records automatically or manually.
- Caches fetched workspace data locally and refreshes it only when requested.
- Reads and edits localized store metadata while keeping Apple and Google copy separate.
- Creates editable App Store versions without submitting them for review.
- Translates complete listings or individual fields using the user's own OpenAI API key.
- Generates localized Google Play release-note blocks with `<language-tag>` markup.
- Reads, uploads, and deletes store screenshots.
- Reads in-app products and subscriptions from both stores.
- Calculates regional pricing using Worldwide PPP, Netflix, or Big Mac indices.
- Applies reviewed regional prices through the official store APIs.
- Reads customer reviews and posts developer replies.
- Shows progress and partial failures for long-running store operations.

Normal operation uses live APIs. Demo mode is clearly identified and does not write to remote stores.

## Important remote-operation behavior

Understand these behaviors before connecting a production account:

- **Save to stores** writes listing metadata remotely.
- Creating an iOS version creates an editable metadata version but does not submit it for App Review.
- Escale first asks Google Play to keep listing edits out of review. Accounts configured for automatic review may reject that option and require Google to send the edit for review automatically. Escale reports when this happens.
- Screenshot deletion removes the remote screenshot before removing it from the local gallery.
- **Apply new pricing** changes production product or subscription pricing in the selected territories.
- Apple may automatically pass subscription price decreases to existing subscribers even when price preservation is selected.
- Google subscriber migration is a separate explicit operation and may notify or otherwise affect subscribers.
- Review replies are public responses posted through the relevant store.
- Google Play tagged release notes are stored locally for the bundle-upload workflow; they are not published by the listing save action.

There is no automatic rollback. Keep a record of the previous state before applying consequential changes.

## Reduce App Review back-and-forth

> **Shipping an iOS app? [AcceptMyApp](https://acceptmy.app/) helps you spot App Review risks before submitting.**
>
> It provides a personalized pre-submission checklist, guideline risk analysis, review-friendly metadata suggestions, and screenshot validation. If Apple has already rejected the app, it can explain the likely cause, help decide whether to fix or appeal, and draft a response for Resolution Center.
>
> [Check your app with AcceptMyApp →](https://acceptmy.app/)

## Requirements

- macOS 14 or newer
- Xcode 16 or newer
- Swift 6
- Xcode Command Line Tools
- [ImageMagick](https://imagemagick.org/) for the recommended `.app` build scripts
- An App Store Connect account and/or Google Play Console account
- An OpenAI API key only if AI-assisted translation or review-reply drafting is required

Escale has no third-party Swift package dependencies.

## Clone and run locally

### 1. Clone the repository

On GitHub, click **Code**, copy the HTTPS repository URL, then run:

```bash
git clone git@github.com:Alex0x47/escale.git
cd escale
```

### 2. Install the local build requirement

Install Xcode from the Mac App Store, select its Command Line Tools, and install ImageMagick:

```bash
brew install imagemagick
```

If command-line tools are not installed yet:

```bash
xcode-select --install
```

### 3. Launch the recommended signed development build

From the repository root:

```bash
./scripts/run-app.sh
```

This builds a debug `.app`, creates its macOS icon, signs it with the first available Apple Development identity, and opens:

```text
dist/Escale.app
```

To choose a particular signing identity:

```bash
ESCALE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" \
./scripts/run-app.sh
```

If no Apple Development identity is installed, the build script uses an ad-hoc signature. An ad-hoc build can run locally, but macOS may request Keychain permission again after the executable changes.

### SwiftPM alternative

For quick UI work that does not need persistent store credentials:

```bash
swift run Escale
```

`swift run` launches a raw SwiftPM executable with a changing ad-hoc code identity. Do not use it for normal connected-account workflows: macOS may repeatedly ask whether the rebuilt executable can read credentials from Keychain. Prefer `./scripts/run-app.sh`.

### Xcode alternative

```bash
open Package.swift
```

Select the **Escale** scheme and run it as a macOS application.

## Build a standalone app bundle

Create an optimized local bundle:

```bash
./scripts/build-app.sh
open dist/Escale.app
```

The script builds the executable, creates `AppIcon.icns`, assembles the bundle, and signs it with an available Apple Development identity. It falls back to an ad-hoc signature when necessary.

An Apple Development signature is suitable for local development. Distributing a trusted build to other Macs requires your own Developer ID Application certificate, hardened runtime configuration, and Apple notarization. This repository does not provide a shared signing identity or notarized binary.

## Run tests

```bash
swift test
```

The default suite tests domain behavior, response decoding, persistence rules, pricing decisions, and local JWT signing without changing store data.

Optional live smoke tests run only when their environment variables are supplied:

```bash
ESCALE_APPLE_ISSUER_ID="..." \
ESCALE_APPLE_KEY_ID="..." \
ESCALE_APPLE_P8_PATH="/absolute/path/AuthKey_ABC123.p8" \
ESCALE_GOOGLE_SERVICE_ACCOUNT_PATH="/absolute/path/service-account.json" \
ESCALE_GOOGLE_PACKAGE="com.company.product" \
ESCALE_OPENAI_API_KEY="sk-..." \
swift test
```

Without those variables, live tests return without contacting Apple, Google, or OpenAI. The live Google test opens and deletes a temporary Play edit; it does not commit it. The OpenAI smoke test checks model access without generating a translation.

Never commit credential files or paste private keys into tests, issues, screenshots, or logs.

## Configure App Store Connect

1. Open **Users and Access → Integrations** in App Store Connect.
2. If necessary, the Account Holder must request App Store Connect API access.
3. Under **Team Keys**, generate an API key with the access required for the intended workflows. App Manager access is the normal starting point; use broader access only when genuinely required.
4. Copy the **Issuer ID** and **Key ID**.
5. Download the `.p8` private key. Apple allows it to be downloaded only once.
6. In Escale, enter both identifiers, choose the matching `.p8` file, and connect.

Official instructions: [Get started with the App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api).

Escale signs short-lived ES256 JWTs locally. Apple credentials are stored in macOS Keychain, not in the repository or workspace cache.

## Configure Google Play

1. Create or select a Google Cloud project.
2. Enable the **Google Play Android Developer API**.
3. Create a service account.
4. Create and download a JSON key for that service account.
5. In Play Console, open **Users and permissions** and invite the service-account email.
6. Grant access only to the required apps.
7. Grant the feature permissions required for the intended workflows, such as app information, store presence, releases, review replies, and product/subscription management.
8. Choose the JSON file in Escale and connect.
9. Add each exact Android package name. The publishing API cannot enumerate every app in an account.

Official instructions: [Google Play Developer API getting started](https://developers.google.com/android-publisher/getting_started).

Escale signs an RS256 service-account assertion locally and exchanges it for an in-memory OAuth token. The service-account document is stored in macOS Keychain.

## Configure AI translation

AI features are optional and use an API key belonging to the user:

1. Create an API key in the [OpenAI dashboard](https://platform.openai.com/api-keys).
2. Open Escale Settings.
3. Save the key in the **OpenAI** section.
4. Optionally run **Test connection**.

Requests go directly from the Mac to `api.openai.com` over HTTPS. The key is stored in Keychain and is never added to workspace data or logs. API usage is billed by OpenAI to the account owning the key.

AI output can be incorrect, misleading, culturally inappropriate, or too long despite validation attempts. Review every translation and reply draft before publishing it.

## Local data and credentials

| Data | Storage |
| --- | --- |
| Apple API credentials | macOS Keychain |
| Google service-account document | macOS Keychain |
| OpenAI API key | macOS Keychain |
| OAuth access tokens | Process memory only |
| Imported store data and pending edits | Local `UserDefaults` workspace cache |
| Generated Google Play release notes | Local workspace cache |

Disconnecting a store removes its saved credential from Keychain. Cached app data remains locally until the workspace is replaced or cleared.

Escale is local-first, but it necessarily sends requests to Apple, Google, public pricing-data sources, and—only when an AI action is requested—OpenAI.

## PPP pricing data

Pricing suggestions may use:

- [World Bank Indicator API](https://datahelpdesk.worldbank.org/knowledgebase/articles/898599-indicator-api-queries)
- [The Economist Big Mac dataset](https://github.com/TheEconomist/big-mac-data)
- [Netflix prices dataset](https://github.com/tompec/netflix-prices)

These are heuristic inputs, not financial advice. Dataset coverage, exchange rates, taxes, store conventions, and purchasing power can change. Suggested prices may be commercially unsuitable even when accepted by a store API.

## Troubleshooting

- **Repeated Keychain prompts:** launch with `./scripts/run-app.sh` and keep the same Apple Development signing identity.
- **Apple 401:** verify that the Issuer ID, Key ID, and `.p8` file belong to the same Team API key.
- **Apple 403:** review the key's App Store Connect role and app access.
- **Apple metadata is read-only:** create or select an editable App Store version.
- **Google authentication succeeds but app import fails:** enable Android Publisher API access and invite the exact service-account email in Play Console.
- **Google 403 for one feature:** Play permissions are feature-specific. Grant the relevant store-presence, release, review, or monetization permission.
- **Google edit conflict:** refresh the selected app and retry with a new edit.
- **Screenshot rejected:** verify device target, pixel dimensions, format, file size, and store count limits.
- **Price rejected:** verify store price-point rules, currency, territory availability, tax behavior, and subscriber-consent requirements.
- **OpenAI request rejected:** verify the key, project access, billing, usage limits, and configured model availability.

## Project structure

```text
Sources/
├── EscaleCore/                   # Public domain, API, security, and state library
├── EscaleUI/                     # Public reusable SwiftUI screens and app shell
└── EscaleCommunityApp/           # Thin community-edition executable and resources

Tests/EscaleCoreTests/             # Domain, decoding, crypto, and smoke tests
scripts/run-app.sh                 # Recommended local development launch
scripts/build-app.sh               # Standalone app-bundle assembly
```

## Community and commercial editions

The package deliberately separates reusable product code from the executable:

- `EscaleCore` owns the models, store clients, credentials, persistence, and orchestration.
- `EscaleUI` depends on `EscaleCore` and owns the reusable community screens.
- `EscaleCommunityApp` depends on both libraries and contains only the macOS entry point and application resources.

A private commercial repository should depend on the public package's `EscaleCore` and `EscaleUI` products, then add `EscaleProKit` and its own thin `EscaleProApp` executable. It should not copy shared files. A bug affecting both editions is fixed and tested here once; the commercial repository then updates its pinned package revision. Commercial-only code never enters this repository, so updating the shared dependency cannot publish it accidentally.

See [Maintaining community and commercial editions](Documentation/EDITIONS.md) for the dependency and release workflow.
See [Escale editions and feature boundaries](Documentation/FEATURES.md) for the Community and Pro capability matrix.

## Contributing

Contributions are welcome, especially:

- Reproducible fixes for Apple or Google API edge cases
- Additional store-state and response fixtures
- Safer previews, validations, and confirmation flows
- Accessibility improvements
- Documentation corrections

Suggested workflow:

1. Fork the repository.
2. Create a focused branch.
3. Make the change without adding credentials or production data.
4. Add or update tests.
5. Run `swift test`.
6. Open a pull request describing the remote behavior affected and how it was verified.

For feature ideas and general feedback, use the [Escale feedback board](https://litefeedback.com/roadmap/Escale). Security issues involving a possible credential leak should not be posted with real secrets or tokens. Revoke any exposed credential immediately.

## Licence

Escale is open-source software licensed under the [Apache License 2.0](LICENSE), using the SPDX identifier `Apache-2.0`.

You may use, inspect, modify, and redistribute it—including as part of a proprietary product—subject to the licence terms. Redistributions must retain the required licence and attribution notices, and modified files must carry prominent change notices. The licence includes an express patent grant but does not grant rights to the Escale name or trademarks. The software is provided without warranty, and the licence contains limitations of liability.

Copyright © 2026 Alexandre Grisey and Escale contributors.

## Non-affiliation

Escale is an independent open-source project. It is not affiliated with, endorsed by, or sponsored by Apple, Google, OpenAI, Netflix, The Economist, or the World Bank. Product names and trademarks belong to their respective owners.
