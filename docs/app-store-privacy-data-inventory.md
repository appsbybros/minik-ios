# App Store privacy-data inventory

Status: source-derived factual input for App Store Connect. The owner is responsible for reviewing current Apple definitions and every linked SDK's release-time disclosures before publishing final answers.

## Per-product source facts

| Product | Firebase features | Ads in source | Remove Ads surface | Local reminders |
| --- | --- | --- | --- | --- |
| MinikPlus | Optional after curated alias selection | Language completion opportunities; disabled by default | Parent Area purchase and restore behind grown-up gate | Parent opt-in, local only |
| MinikPlusEnglish | Same as MinikPlus, with separate score collection and shared streak collection | Same Language opportunities; disabled by default | Parent Area purchase and restore behind grown-up gate | Parent opt-in, local only |
| MinikMathPlus | None; Firebase SDK/config absent | Only the included Ping Pong activity can report an opportunity; disabled by default | Parent Area purchase and restore behind grown-up gate | Parent opt-in, local only |
| MinikMath | None; Firebase SDK/config absent | Interstitial after a finished round or Ping Pong game on Android Minik Math's schedule (never the first two rounds, at least two minutes apart) | Parents page purchase and restore behind grown-up gate | No reminders |
| MinikPingPong | Anonymous Auth and private RTDB friendly games/tournaments in `minikswish/minikPingPong`; no leaderboard | Modern completed-match cadence; Debug test ads only, Release disabled | Native StoreKit purchase, restore and Apple offer-code redemption | No reminders |

## Data handling facts for the questionnaire

| Function | Data/process | Sent off device by app/SDK? | Linked/tracking source posture | Purpose | Owner review needed |
| --- | --- | --- | --- | --- | --- |
| Firebase anonymous Auth (Language and standalone Modern Ping Pong) | Firebase anonymous UID | Yes, to Firebase | Technical identifier; app declares collected data linked, not tracking | App functionality/security transport | Confirm Apple's current identifier category and Firebase SDK disclosure |
| Private leaderboard ownership (Language only) | A private association between the Firebase anonymous UID and an opaque versioned per-profile participant ID | Yes, to Firestore; not publicly readable/displayed | Technical identifier linkage, not tracking | Protect participant writes/deletion while allowing multiple local profiles | Confirm final Apple category mapping and legal disclosure wording |
| Public leaderboard (Language only) | Generated alias, optional curated avatar ID, score, streak/correct-answer value, opaque participant ID, app ID `3`, server timestamp | Yes, to Firestore | App manifest declares User ID and Gameplay Content as linked, not tracking | Public leaderboard app functionality | Confirm final Apple category mapping and child-directed legal basis |
| Modern Ping Pong private multiplayer | Curated nickname/avatar/character ID, anonymous UID, room code, roster, presence, Ready state, schedule/results, action/checkpoint state, timestamps and nickname/slot reservations | Yes, to `minikswish` RTDB under `minikPingPong/` | User ID and Gameplay Content linked for app functionality, not tracking; room participants can see each other | Private games, reconnect and tournaments | Verify store disclosures and retention/deletion process before release |
| Local child name/progress/settings | Local name, learning progress, levels, alias preference, pending best result, reminders/ad cadence | No app-owned upload path | Local-only | App functionality | Verify backup behavior and whether policy should discuss device backups |
| StoreKit | Product request, transaction/verification result, current entitlement, restore/sync | StoreKit communicates with Apple; app keeps entitlement cache locally | No app server receives purchase data in current source | Purchase/restore app functionality | Decide App Store privacy answer using Apple's current StoreKit guidance |
| Google Mobile Ads | SDK request/response and SDK-described technical data, only if all release gates and IDs are enabled | Potentially, if enabled | App forces child/under-age/G/non-personalized and contains no ATT/IDFA request; third-party SDK facts still govern | Third-party advertising | Keep disabled until owner reviews current Google SDK data practices, Kids/category policy, consent obligations, and Apple answers |
| Local notifications | Authorization status and one product-scoped weekly local request | No remote push/FCM path | Local-only | App functionality | None beyond accurate policy description |

The app-owned Language privacy manifest currently declares `NSPrivacyCollectedDataTypeUserID` and `NSPrivacyCollectedDataTypeGameplayContent`, linked to an identity and used for app functionality, with tracking false. Math remains unchanged. The new Modern Ping Pong manifest also declares linked User ID and Gameplay Content for app functionality, with tracking false. Simple embedded mode does not initialize the Ping Pong Firebase client. Every app declares app-only `UserDefaults` access using reason `CA92.1`. Archive-time privacy reports must be reviewed because third-party SDK manifests can add disclosures beyond app-owned manifests.

## Answers that must not be guessed in source

- Whether each app will ship with Google Mobile Ads enabled. If enabled, answer using the exact release SDK behavior and Google's then-current disclosure, not merely Minik's request flags.
- The final App Store Connect classification of Firebase identifiers, public alias/avatar and gameplay records under Apple's current definitions.
- Whether Apple-mediated StoreKit activity requires any developer-declared Purchase data for this specific architecture.
- Kids Category selection and age band for each listing; this affects advertising and privacy review and is not inferred from child-friendly design.
- Territory-specific parental-consent/legal basis, privacy-controller contact details, retention rules, deletion handling, and cross-border/service-provider wording.

No listing that enables the Language leaderboard should answer “No, we do not collect data from this app.” App Store Connect answers must include relevant third-party partner practices as they exist in the submitted binary.

## Modern Ping Pong update — 2026-09-28

See [the implementation handoff](modern-pong-ios-handoff.md). The standalone Apple Firebase registration is now created. Debug uses Google test inventory; Release ads remain disabled. Local room notices/ads preferences are separate from legacy progress. Private room cleanup runs when a connected client starts, removes inactive unoccupied rooms after fourteen days under the existing rules, and is not a guaranteed server-scheduled retention deadline. Nickname/profile records are separate; do not promise that room cleanup deletes those records. No privacy website was published during this implementation.
