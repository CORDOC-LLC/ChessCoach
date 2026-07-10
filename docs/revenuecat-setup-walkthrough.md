# RevenueCat + App Store paywall — step by step

Split by who does what. **You** do the dashboard/account steps (I have no
access to App Store Connect or the RevenueCat dashboard). **Me** means tell
me the value/confirm the step and I'll write the code.

Design locked in this session:

| Channel | Coach backends available |
|---|---|
| Local (Xcode/devicectl install) | ChessCoach Pro (debug config) **and** Gemini BYOK, plus an easy-to-skip paywall preview reachable from Settings (for testing the real purchase flow without it blocking normal dev use) |
| TestFlight | Gemini BYOK **only** — no paywall surface at all |
| App Store (production) | ChessCoach Pro (RevenueCat subscription) **only** — no BYOK |

This is already wired in code (`BuildChannel.swift`, `CoachOrchestrator`,
`CoachSettingsView`) — shipped in commit `ce40d27`.

---

## Step 1 (you) — Apple side: the two subscription products

In **App Store Connect → your app → Subscriptions**:

1. Create a Subscription Group, e.g. "ChessCoach Pro".
2. Add two auto-renewable subscriptions in it:
   - Monthly — target ~$8 (nearest tier is $7.99 or $8.99)
   - Annual — target ~$49 (nearest tier is $49.99)
3. Use permanent product IDs, e.g.:
   - `com.cordoc.gemmachess.pro.monthly`
   - `com.cordoc.gemmachess.pro.annual`
4. Decide if you want a free trial (a 7-day trial on the annual plan is the
   standard lever for converting a $49 upfront ask).

**Tell me:** the two product IDs you actually used (in case they differ from
above), and whether you added a trial.

---

## Step 2 (you) — RevenueCat: project + products + entitlement + offering

1. Create a RevenueCat account/project (if you haven't already) at
   [app.revenuecat.com](https://app.revenuecat.com).
2. **Connect App Store Connect**: Project Settings → Integrations → App Store
   Connect, upload the App Store Connect **API key** (a *different* key than
   the one we use for TestFlight uploads — this one just needs to read
   subscription status, generate it fresh under Users and Access →
   Integrations, or reuse one scoped with the right permissions).
3. **Import your two products** (RevenueCat can pull them once App Store
   Connect is connected — Products tab → should show your monthly/annual
   subscriptions once ASC processes them, which can take a few hours after
   creating a new product).
4. **Create an Entitlement** named exactly `pro` (this must match, since the
   backend already defaults to `CHESSCOACH_ENTITLEMENT_ID=pro` — see
   `chesscoach-gateway/.env.example`). Attach both products to it.
5. **Create an Offering** (e.g. "default") with two Packages — one for
   monthly, one for annual — pointing at the two products.
6. Grab two keys from Project Settings → API Keys:
   - **Public SDK key** (starts with `appl_`) — goes in the iOS app.
   - **Secret key with V2 permissions** — goes in the *backend* (Vercel env
     var), not the app. Already has a home:
     `CHESSCOACH_REVENUECAT_SECRET_KEY` in `chesscoach-gateway`.
7. Set up the **webhook**: Project Settings → Integrations → Webhooks → add
   `https://api.chesscoach.im/api/revenueCatWebhook`, and set a shared
   secret — that goes in `CHESSCOACH_REVENUECAT_WEBHOOK_SECRET` (backend env
   var, alongside the secret key).

**Tell me:** the public SDK key (`appl_...`) and the Offering identifier you
named it — that's what the app code needs. The secret key + webhook secret
go straight into Vercel's env vars for `chesscoach-gateway` (you can set
those yourself via `vercel env add`, or tell me and I'll do it with your
`vercel` CLI session).

---

## Step 3 (me) — client integration, once you hand me the SDK key

- Add the RevenueCat SDK (`RevenueCat` via SPM) to `GemmaChessCore`.
- Replace `ManagedCoachStore.debugAppUserId()` with
  `Purchases.shared.appUserID` as the real `appUserId` sent to the backend.
- Build the paywall screen: Monthly/Annual toggle, live pricing pulled from
  the Offering, "Restore Purchases", tasteful design matching the rest of
  the app (glass cards, same accent/gold palette already established).
- Wire entry points per the channel design above:
  - **App Store production**: the "ChessCoach Pro" section in
    `CoachSettingsView` becomes the real paywall (replaces the "coming
    soon" placeholder) — tapping it shows the purchase screen.
  - **Local dev**: a "Preview Paywall" button appears in that same section
    (alongside the existing debug fields) so you can test the real
    RevenueCat purchase flow (sandbox) without it blocking normal
    debug-token-based testing.
  - **TestFlight**: nothing changes — the managed-coach section stays
    hidden entirely, per `BuildChannel.allowsManagedCoach == false` there.
- Wire `CoachOrchestrator`/`ManagedCoach` to check the RevenueCat
  entitlement (`Purchases.shared.customerInfo().entitlements["pro"]`)
  instead of (or in addition to, during transition) the debug bypass token.

---

## Step 4 (you) — sandbox test purchase

Once Step 3 ships, test on a real device signed into a **Sandbox Apple ID**
(App Store Connect → Users and Access → Sandbox Testers, or use StoreKit
Testing in Xcode for a faster loop first). Confirm:
- Purchase completes and `pro` entitlement shows active in RevenueCat's
  dashboard (Customers tab).
- The app unlocks the managed coach immediately after purchase.
- Restore Purchases works on a fresh install.

---

## Suggested order

Steps 1 and 2 are pure dashboard work and can happen in parallel with
anything else. The moment you have the public SDK key from Step 2, ping me
and I'll do Step 3 in one sitting.
