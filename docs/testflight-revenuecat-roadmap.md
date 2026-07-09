# TestFlight + RevenueCat launch roadmap

Split by who does what. The backend side (`chesscoach-gateway`) already expects
RevenueCat as the entitlement source of truth — this is configuration, not new
backend work.

Pricing target: **$8/month**, **$49/year**.

## 1. Apple Developer / App Store Connect (you)

- Agree to the Paid Applications Agreement and add banking/tax info in App
  Store Connect, if not already done — required before any subscription (even
  sandbox-tested ones) can go live.
- Create a Subscription Group (e.g. "ChessCoach Pro") with two auto-renewable
  subscriptions inside it:
  - Monthly — $7.99 or $8.99 (Apple's price tiers don't include a flat $8.00;
    pick whichever's closer to the target)
  - Annual — $49.99 (nearest tier to $49)
- Use clear, permanent product IDs now (they can't be changed once used), e.g.
  `com.cordoc.gemmachess.pro.monthly` / `com.cordoc.gemmachess.pro.annual`.
- Decide on a free trial (a 7-day trial on the annual plan is the most common
  lever for converting a $49 upfront ask — worth considering even if skipped
  on monthly).

## 2. RevenueCat (you)

- Create a RevenueCat project, connect the App Store Connect API key so it can
  read subscription status.
- Create an entitlement named exactly `pro` (matches the backend's default
  `CHESSCOACH_ENTITLEMENT_ID` — name it something else and just set that env
  var instead).
- Attach both products to that entitlement, and create an Offering with a
  monthly + annual package.
- Grab the SDK public API key (distinct from the secret key) — needed for the
  client.
- Create a secret key with V2 permissions and a webhook shared secret — set
  these as `CHESSCOACH_REVENUECAT_SECRET_KEY` / `CHESSCOACH_REVENUECAT_WEBHOOK_SECRET`
  in the Vercel project's env vars, and point a RevenueCat webhook at
  `https://api.chesscoach.im/api/revenueCatWebhook`.

## 3. Client wiring (me — tracked as plan unit U6)

- Add the RevenueCat SDK (SPM) to the app, replace `ManagedCoachStore`'s debug
  UUID with `Purchases.shared.appUserID`.
- Build a real paywall screen (Monthly/Annual toggle, live pricing from the
  Offering, "Restore Purchases") to replace the current debug-token config
  screen for real users.
- Wire `CoachOrchestrator`/`ManagedCoach` to check the RevenueCat entitlement
  instead of (or alongside, during transition) the debug bypass token.
- Remove/hide the debug backend-URL and bypass-token fields from Coach
  Settings for release builds, or gate them behind a debug build flag.

## 4. TestFlight submission checklist

- Privacy: board-scanning uses `PhotosPicker` (the system picker), so no
  camera or photo-library usage description is needed — already the right
  call.
- Add/confirm a Privacy Manifest (`PrivacyInfo.xcprivacy`) covering network use
  (Gemini/Gateway calls) — Apple requires this now.
- Export compliance: standard HTTPS only, so "no" on the encryption
  questionnaire.
- Archive + upload via Xcode Organizer (or via the App Store Connect tooling
  available once there's a version/build to attach metadata to).
- Internal TestFlight testers (your own team) need no review; external
  testers require a quick Beta App Review.

## Suggested next unblocking step

Get the RevenueCat entitlement + Offering created and the two API keys in
hand — that's the one thing gating the client wiring (U6), and it's pure
dashboard configuration, no code.
