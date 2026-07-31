# Contributing to Escale

Thank you for helping improve Escale Community.

## Scope

This repository contains only the Community application. Contributions should
not add dormant commercial implementations, entitlement gates, paywalls,
licence management, or private distribution credentials. Use the public
feedback board for product proposals before investing in a large change.

## Development workflow

1. Fork the repository and create a focused branch.
2. Do not use real store data, credentials, customer content, or production
   identifiers in code, tests, fixtures, screenshots, logs, or issues.
3. Add or update tests for behavioral changes.
4. Run `swift test` on an Apple silicon Mac with macOS 14 or newer.
5. Open a pull request that explains the user impact, remote API behavior, and
   verification performed.

Keep changes focused and preserve explicit confirmation for consequential store
writes. Avoid unrelated formatting churn.

## Versions and releases

Do not bump `VERSION` in an ordinary pull request. Maintainers update it
explicitly as part of a release. The optional tracked pre-commit hook validates
the file but never mutates it.

## Licence

Unless explicitly stated otherwise, intentionally submitted contributions are
licensed under Apache-2.0 under section 5 of the project licence.

Report security issues privately as described in [SECURITY.md](SECURITY.md).
