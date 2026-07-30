# Escale editions and feature boundaries

The Community edition must remain a complete manual store-management workflow. Entitlements gate Pro operations, not access to user data or the ability to build and modify the open-source application.

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

## Pro

| Capability | Entitlement |
| --- | --- |
| Apply reviewed PPP prices to connected stores | `applyRegionalPricing` |
| Translate fields or release notes across all locales in the selected app | `bulkTranslations` |
| Save and reuse What’s New templates across apps and locales | `releaseNoteTemplates` |
| Draft customer-review replies with AI | `draftReviewReplies` |
| Upload an Android App Bundle and create a Google Play draft release | `uploadGooglePlayBundle` |

`EscaleCommunityApp` always creates its workspace with `CommunityEntitlements`. A private commercial executable supplies its own `EscaleEntitlementProviding` implementation after validating a licence.

Feature checks live in both places:

1. SwiftUI checks display a contextual Escale Pro explanation before starting a gated action.
2. `WorkspaceStore` checks prevent a gated remote operation from executing if a UI entry point omits its check.

Only shipped and enforced capabilities belong in `EscaleFeature` and in public
edition comparisons. Planned ideas must not be presented as current Pro
features.

For PPP pricing, Community calculation and preview remain available; only
applying the reviewed prices to remote stores is gated.
