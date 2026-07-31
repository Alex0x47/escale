# Security policy

## Supported versions

Security fixes are applied to the current release and the latest `main` branch.
Older releases may not receive patches.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability, exposed
credential, or report that contains private store data. Email
`pro@alexandre-grisey.fr` with:

- the affected version and macOS version;
- a concise description and reproducible steps;
- the impact you believe is possible; and
- any suggested remediation.

Do not include active Apple, Google, OpenAI, Polar, or other credentials. Revoke
any credential that may already have been exposed.

You should receive an acknowledgement within five business days. Alexandre
Grisey will investigate, coordinate a fix and disclosure timeline when the
report is valid, and credit reporters who request attribution. Please allow a
reasonable remediation period before public disclosure.

## Security model

Escale stores long-lived credentials in macOS Keychain and keeps OAuth access
tokens in process memory. Its connected workflows necessarily send requests to
Apple, Google, OpenAI when explicitly invoked, and the documented public
pricing-data sources. Review consequential writes in Escale and verify them in
the official store console.
