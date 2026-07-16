# feat: ChessCoach marketing/download website

**Type:** feat
**Depth:** Standard
**Target repo:** A **new, separate, private repo** (`chesscoach-website`) for all website work; this repo (ChessCoach) only for a small follow-up URL fix once the site is live (see Scope Boundaries)

---

## Summary

ChessCoach's `PaywallView` already links to `chesscoach.im/terms` and `chesscoach.im/privacy` — placeholder URLs that don't exist yet, which Apple requires to be real, functioning pages before the subscription can go live. This plan builds the marketing/download website that will host those pages plus a landing page, pricing, and an App Store download CTA, deployed to Vercel at the `chesscoach.im` apex domain (free — the existing `chesscoach-gateway` backend already lives on the `api.chesscoach.im` subdomain, confirmed via `managedCoachProductionURL` in `Sources/GemmaChessCore/Coach/ManagedCoachStore.swift`, so there's no domain conflict to resolve).

---

## Problem Frame

The GemmaChess repo is public and GPLv3-licensed (it links Stockfish). The website is pure marketing/legal content with no reason to be open source, and mixing it into the public repo risks accidentally publishing anything business-sensitive (pricing experiments, unreleased copy, analytics keys). This plan defines a new, separate, private repo for the website — deliberately kept apart from `chesscoach-gateway` too, even though both are private and both deploy to Vercel, because `chesscoach-gateway` is a small, tested, payment/entitlement-critical service (StoreKit JWS verification, Neon usage ledger, App Attest) that shouldn't take on review overhead or blast radius from routine marketing content changes.

---

## Requirements

- **R1**: A live, real Privacy Policy page and Terms of Use page, reachable at the exact URLs `PaywallView` already links to (`https://chesscoach.im/privacy`, `https://chesscoach.im/terms`) — this is the requirement Apple review is actually blocking on.
- **R2**: A single-page landing site, organized into sections (not separate marketing pages), that explains what ChessCoach is and why it's different, mirroring the app's own onboarding messaging (`Sources/GemmaChessCore/UI/OnboardingView.swift`'s four pages: engine-grounded coaching, best-move hints, board scanning, free puzzles) so app and website tell the same story.
- **R2b**: A dedicated section making the case *for* coaching explicitly, not just describing features: what goes wrong when someone learns chess alone (repeating the same mistakes without knowing it, no explanation of *why* a move was wrong) contrasted with what ChessCoach's engine-grounded coaching fixes. This is the section meant to actually convert a visitor, not just inform them.
- **R2c**: A single source of truth for brand assets (logo, wordmark, color tokens, product name/tagline) that every component and page reads from, so a future logo or color change is a one-file edit, not a find-and-replace across the codebase.
- **R3**: A pricing section showing the three ChessCoach Pro plans exactly as configured in App Store Connect and RevenueCat: Weekly $3.99, Monthly $8.00, Annual $59.00.
- **R4**: A "Download on the App Store" badge/CTA, visually matching the badge already used on DictaWiz's website, linking to the ChessCoach App Store listing.
- **R5**: The website's source code, copy, and any business-sensitive content (pricing rationale, analytics, unreleased features) never appear in the public GemmaChess repo.
- **R6**: The site deploys to the existing CORDOC LLC Vercel team, at the `chesscoach.im` domain, without disrupting `chesscoach-gateway`'s existing `api.chesscoach.im` deployment.
- **R7**: Real app screenshots (device-framed, showing Play mode, the coach, board scanning, etc.) appear in the Hero and/or Feature sections. The user will supply these screenshots later; this plan builds clearly-marked placeholder slots now so dropping the real assets in is a content change, not a layout change. The same screenshot set is intended for reuse as the App Store Connect listing's screenshots (see U4a/U2).

---

## Key Technical Decisions

### KTD-1: New, separate, private repo (`chesscoach-website`) — not merged into `chesscoach-gateway`, not inside GemmaChess

**Decision**: Create a new private GitHub repo under CORDOC-LLC for the website. It does not live inside the GemmaChess directory tree in git (may sit as a gitignored sibling/nested folder on disk, same pattern as `chesscoach-gateway/` today), and it is not merged into `chesscoach-gateway`.

**Rationale**: Confirmed with the user directly. `chesscoach-gateway` is a small, stable, security/payment-critical service (KTD-1 of the paid-tier plan, `docs/plans/2026-07-08-001-feat-paid-tier-metering-backend-plan.md`, already established the "keep sensitive backend isolated" principle for the public/private boundary). Folding a Next.js marketing site into that repo would mean every copy tweak or design iteration touches the same repo as StoreKit verification and the usage ledger, raising review overhead for the part of the system that can least afford a careless change. DictaWiz's website repo (`free-voice-reader/FreeVoiceReader`) does bundle its own backend, but that backend *is* the product's data layer, not a separate metering proxy sitting in front of Apple's billing APIs — not a directly comparable case.

**Alternative considered**: Merge into `chesscoach-gateway`. Rejected per the above — the user was asked directly and chose separate repos.

### KTD-2: Next.js 16 App Router, static-first

**Decision**: Next.js 16.2.x (latest stable as of this plan) with the App Router, TypeScript, and Tailwind CSS. All pages are static/server-rendered at build time — no client-side data fetching, no database, no auth. Content (pricing, feature copy) lives in local TypeScript/MDX files, not a CMS.

**Rationale**: The site has no dynamic, per-user data — every visitor sees the same landing page, pricing, and legal text. Static generation is the simplest, cheapest, fastest option, and keeps the site's dependency surface (and therefore its security/maintenance burden) minimal. A CMS or database would be solving a problem this site doesn't have.

### KTD-3: Domain split — `chesscoach.im` for the website, `api.chesscoach.im` stays the gateway (no change needed)

**Decision**: Point the new Vercel project at the `chesscoach.im` apex domain (and `www.chesscoach.im`, redirecting to apex). The `chesscoach-gateway` Vercel project keeps its existing `api.chesscoach.im` domain, completely unaffected.

**Rationale**: `ManagedCoachStore.managedCoachProductionURL` is already `"https://api.chesscoach.im"` — the gateway has never used the apex domain, so there's nothing to migrate or coordinate. This was a candidate open question in the original feature request; it turned out to already be resolved by existing infrastructure.

### KTD-4a: Visual design uses the app's "Daylight" theme palette

**Decision**: The website's color scheme is drawn directly from `Theme.daylight` in `Sources/GemmaChessCore/Theme/Theme.swift` — accent `#5b8c6e` (sage green), accent2 `#bd7f56` (warm terracotta/wood), background `#f2ecdf` (parchment), surface `#fffdf8` (warm white), text `#2f2a22` (dark walnut), board squares `#ece4d2`/`#a7b795`. Same relative-luminance contrast logic the app uses (`onAccentColor`, `mutedTextColor`/`faintTextColor` opacity steps) carries over for button/text contrast on the site.

**Rationale**: User request -- reads as a chess/wood-board palette (sage and terracotta evoke a wooden board and felt-lined pieces) and gives the website unmistakable visual continuity with the app's own light preset, rather than inventing a separate brand palette that has to be kept in sync by hand. `Theme.daylight` is a light theme, which suits a marketing site better than the app's darker presets (`Night Market`, `The Study`) — daylight is the natural "public-facing" choice among the four.

### KTD-5: Single-page site with a brand/content source of truth

**Decision**: The marketing site is one page (`app/page.tsx`) composed of stacked sections — Hero, "Why a coach" (R2b), Features, Pricing, final CTA, Footer — navigated via in-page anchor links, not a multi-page site. `/privacy` and `/terms` remain separate routes since they need stable, independently-linkable URLs (R1), but carry no site navigation of their own beyond a link back to the landing page. All brand constants (logo/wordmark asset, product name, tagline, color tokens) live in one file, `content/brand.ts`, imported by every component that needs them — nothing hardcodes a color hex, the app name, or a logo path directly in a component.

**Rationale**: User request, twofold: (1) a single page with sections keeps a marketing/download site simple, matching the site's actual scope — there's no reason for a visitor to navigate between pages when everything fits above a few scrolls; (2) a single source of truth for brand assets means the logo or palette can change once (in `content/brand.ts` and the Tailwind config it's paired with) instead of hunting through every component. This directly extends KTD-4a's Tailwind color tokens into a broader brand file that also owns the logo asset and product copy constants, not just colors.

**Logo source**: use ChessCoach's own actual app icon, `Apps/GemmaChessiOS/Assets.xcassets/AppIcon.appiconset/icon_1024.png` (1024×1024, the real submitted App Store icon) -- not a placeholder mark. Export/optimize a web-appropriate size from this source for `public/logo.svg`/`logo.png`; the prototype's nav/footer mark is currently a plain color swatch (`background:#5b8c6e` square) as a placeholder for this real icon.

### KTD-4: App Store badge — Apple's real official artwork, degrades gracefully pre-launch

**Decision**: Use Apple's actual official "Download on the App Store" badge SVG, copied directly from `free-voice-reader/FreeVoiceReader/public/images/ios-app/app-store-badge.svg` (Apple's own marketing artwork, already vetted and in production use on DictaWiz's site) into this repo's `public/app-store-badge.svg` — not redrawn or approximated. Before the app is approved and live, the badge links to a "Coming soon" state (e.g., a disabled/greyed badge or a waitlist mailto) rather than a broken or wrong App Store URL; once the numeric App Store ID is known (app `6789547867` is already registered in App Store Connect, confirmed via the App Store Connect API work done earlier this session — the public listing just isn't live yet), swap in the real `https://apps.apple.com/app/id6789547867` link.

**Rationale**: R4 needs a real badge, but the app isn't approved yet — shipping a link to a 404 App Store page would look broken. The App Store numeric ID is already known and stable (it doesn't change when the listing goes live), so the swap-in later is a one-line content change, not new work. Reusing the exact same SVG file (rather than regenerating from Apple's badge tool) guarantees pixel-identical badge artwork to what's already shipped and approved on another CORDOC LLC property.

### KTD-6: Design source — Claude Design handoff bundle is the authoritative visual reference

**Decision**: The user produced a full HTML/CSS/JS prototype via Claude Design and handed off a bundle (`ChessCoach.dc.html`, `privacy.dc.html`, `terms.dc.html`, plus a larger `ChessCoach Site.dc.html` variant) that implements this plan's structure almost exactly — same Daylight palette, same one-page section order (Hero → Why a Coach → Features → Pricing → Final CTA → Footer), same benefit-ladder copy from KTD-5/U2, same $3.99/$8/$59 pricing, same placeholder-styled Privacy/Terms pages. This HTML/CSS is the **pixel-accurate visual reference** for implementation -- recreate its visual output faithfully in Next.js/Tailwind (per the bundle's own README: "recreate them pixel-perfectly... don't copy the prototype's internal structure unless it happens to fit"), rather than re-deriving layout, spacing, or copy from this plan's prose alone.

**Concrete details the prototype fixes that this plan left more general:**
- **Typography**: Spectral (serif, weights 300/400/500/600, italic 400) for body/headings, IBM Plex Mono (400/500) for labels/eyebrows/nav/buttons -- both via Google Fonts. This replaces this plan's earlier generic "a serif display font" guidance with an exact pairing.
- **Nav**: sticky, translucent/blurred header with in-page anchors to `#why`, `#features`, `#pricing`, plus a "GET THE APP" button anchored to `#download`.
- **Hero**: eyebrow badge reading "POWERED BY STOCKFISH · NOT A GUESSING CHATBOT" (the engine-grounded proof point, exactly as specified in KTD-5/U2 -- supporting text, not the headline), headline "Stop making the same mistakes.", device-framed screenshot placeholder alongside the copy.
- **Why a Coach**: a callout card ("A real engine, not a chatbot") above a 2x2 grid of the four benefit-ladder points from U2, each numbered.
- **Screenshot placeholders**: dashed-border boxes with a centered label (e.g. "SCREENSHOT · move analysis") -- the concrete pattern `ScreenshotFrame` (U2) should implement.
- Both `privacy.dc.html` and `terms.dc.html` already contain the section headers this plan's U4 calls for (Information we collect / How we use it / Your choices; Using ChessCoach / Subscriptions & billing / Disclaimers) with placeholder body text marked for replacement -- use these as the starting structure for U4's real copy.

**Rationale**: The user explicitly designed this in Claude Design before handoff specifically so implementation wouldn't have to invent visual details from prose. Treating it as the reference (not this plan's earlier generic descriptions) avoids drifting from what the user actually approved.

---

## Output Structure

```text
chesscoach-website/                    (new private repo)
├── app/
│   ├── layout.tsx                     Root layout: fonts, metadata, analytics
│   ├── page.tsx                       ONE page: stacks every section below (KTD-5)
│   ├── privacy/
│   │   └── page.tsx                   Privacy Policy (R1) -- standalone route, no nav of its own
│   ├── terms/
│   │   └── page.tsx                   Terms of Use (R1) -- standalone route, no nav of its own
│   └── globals.css
├── components/
│   ├── sections/
│   │   ├── Hero.tsx
│   │   ├── WhyACoach.tsx              R2b -- the risk-of-learning-alone case
│   │   ├── FeatureGrid.tsx            Mirrors OnboardingView's 4 pages
│   │   ├── PricingTable.tsx           Weekly/Monthly/Annual (R3)
│   │   ├── FinalCTA.tsx
│   │   └── Footer.tsx
│   ├── AppStoreBadge.tsx              KTD-4
│   └── Logo.tsx                       Single place the logo asset is rendered from
├── content/
│   ├── brand.ts                       R2c -- logo path, name, tagline, color tokens (KTD-5)
│   ├── features.ts                    Feature copy, kept out of components for easy editing
│   └── pricing.ts                     Plan data, mirrors App Store Connect config
├── public/
│   ├── logo.svg
│   ├── app-store-badge.svg
│   ├── og-image.png
│   └── screenshots/                   R7 -- placeholder slots until real assets arrive
│       └── README.md                  Expected filenames, dimensions, device frame notes
├── next.config.ts
├── package.json
├── tsconfig.json
└── vercel.json                        (only if non-default settings needed)
```

---

## Implementation Units

### U1. Repo scaffold + Vercel project

**Goal**: A new private GitHub repo with a working Next.js 16 App Router skeleton, deployed to Vercel and reachable at a `*.vercel.app` preview URL.

**Requirements**: R5, R6, R2c

**Dependencies**: None

**Files**:
- New repo root: `package.json`, `next.config.ts`, `tsconfig.json`, `app/layout.tsx`, `app/page.tsx` (placeholder), `.gitignore`
- `content/brand.ts` — logo asset path, product name, tagline, and the Daylight color tokens re-exported as typed constants
- `components/Logo.tsx` — the one component that renders the logo, reading its asset path from `content/brand.ts`
- `public/logo.svg`/`logo.png` — exported from the real app icon (see KTD-5's Logo source note)
- `public/app-store-badge.svg` — copied verbatim from `free-voice-reader/FreeVoiceReader/public/images/ios-app/app-store-badge.svg` (KTD-4)
- `README.md` — mirror `chesscoach-gateway/README.md`'s pattern (what this is, why it's private, how it relates to the public ChessCoach repo)

**Approach**: `create-next-app` with TypeScript + Tailwind + App Router, on Next.js 16.2.x. Initialize as a private GitHub repo under the CORDOC-LLC org. Connect to the existing CORDOC LLC Vercel team as a new project (not reusing `chesscoach-gateway`'s project). Wire the Daylight palette (KTD-4a) into Tailwind's theme config (`accent`/`accent2`/`bg`/`surface`/`text` custom colors matching `Theme.daylight`'s hex values, cross-checked against the prototype's exact CSS in `ChessCoach.dc.html`), then re-export those same values from `content/brand.ts` alongside the logo path and product copy constants (KTD-5) so every later unit imports from one place instead of duplicating hexes or the app name inline. Register the Spectral + IBM Plex Mono Google Fonts pairing from the prototype (KTD-6) in `app/layout.tsx`.

**Patterns to follow**: `chesscoach-gateway/README.md` and its `vercel.json` for how this team structures a private, Vercel-deployed repo's docs and config. `ChessCoach.dc.html` (design handoff bundle, KTD-6) for exact colors, spacing, and typography values.

**Test scenarios**:
- Test expectation: none -- scaffolding, no behavior yet.

**Verification**: `next build` succeeds locally; Vercel preview deployment loads the placeholder page.

---

### U2. Landing page — hero + "why a coach" + feature sections, one page

**Goal**: The single page a visitor lands on: a hero, an explicit case for why coaching matters, the feature highlights, and an App Store CTA — all sections of one page (KTD-5), not separate routes.

**Requirements**: R2, R2b, R4, R7

**Dependencies**: U1

**Files**:
- `app/page.tsx` — assembles the sections below in order
- `components/sections/Hero.tsx`, `components/sections/WhyACoach.tsx`, `components/sections/FeatureGrid.tsx`, `components/sections/FinalCTA.tsx`
- `components/AppStoreBadge.tsx`
- `components/ScreenshotFrame.tsx` — device-framed image slot; renders a clearly-marked placeholder (dashed border + filename label, e.g. "hero-play-mode.png") when the expected file under `public/screenshots/` is missing, and the real screenshot once it exists -- no code change needed when assets arrive, just drop the file in
- `content/features.ts`
- `public/screenshots/README.md` — exact filenames/dimensions this unit expects (hero shot + one per feature card), so the user knows what to hand off

**Approach**: Section order: Hero (name, one-line pitch, App Store badge) → **Why a Coach** (R2b — the section this unit exists to get right) → Feature highlights (four cards mirroring `OnboardingView.swift`'s pages: engine-grounded coaching, best-move hints with the "why," board scanning, free puzzles) → final CTA repeating the App Store badge.

**Messaging framework (from the marketing-positioning brainstorm this plan was updated from):**
- **Persona**: the plateaued casual player -- plays regularly, knows the rules, keeps losing the same way, doesn't know why. Not the total beginner, not the tournament competitor.
- **Hero headline** leads with the pain point directly: *stop making the same mistakes*. This is the one thing a plateaued player recognizes instantly.
- **Why a Coach section** carries the rest of the benefit ladder in order: (1) stop repeating mistakes → (2) understand *why* a move was wrong, not just that it was → (3) start seeing strategies and understanding openings as patterns click over time → (4) a quiet prestige beat (being the person who actually knows what they're doing) → (5) close on enjoyment -- understanding chess makes it more fun, not more homework. Prestige and enjoyment are closing notes, not headline material.
- **"Engine-grounded, not a chatbot guessing" is proof, underneath the pitch, never the headline** -- one supporting line near benefit (1)/(2) ("every explanation traces back to what Stockfish actually calculated"), not the hero copy. Nobody's problem is "I want an engine"; it's "I keep losing and don't know why."

This section is the site's actual conversion argument; the feature grid below it is supporting detail, not the lead.

**Patterns to follow**: `ChessCoach.dc.html` (design handoff, KTD-6) is the primary visual/copy reference -- its Hero, Why a Coach, and Feature grid sections already contain the exact headline, benefit-ladder copy, and layout to implement; recreate its visual output in Tailwind rather than re-deriving from scratch. `Sources/GemmaChessCore/UI/OnboardingView.swift`'s four `OnboardingPage` entries remain the source of truth for feature-grid *substance* if the prototype's wording needs adjusting. `Sources/GemmaChessCore/Coach/ManagedCoach.swift`'s and `CoachOrchestrator`'s own framing ("the engine calculates every line first — your coach only ever writes about what the engine actually found") for the "why a coach" section's core claim, so the website's pitch and the app's own onboarding claim are the same sentence, not two different marketing voices.

**Test scenarios**:
- Happy path: page renders Hero → Why a Coach → Feature grid → Final CTA in that order, as one scrollable page with no route changes between them.
- Happy path: hero headline leads with the "stop making the same mistakes" hook, not a generic tagline or the engine-grounded claim.
- Happy path: Why a Coach section covers the benefit ladder in order (mistakes → why → strategies/openings → prestige → enjoyment), with the engine-grounded claim present only as a supporting line, not the section's lead sentence.
- Happy path: all four feature cards render the app's actual onboarding copy (not placeholder text).
- Happy path: App Store badge renders in its pre-launch "Coming soon" state (KTD-4) until the App Store ID is wired in.
- Happy path: each `ScreenshotFrame` slot renders its labeled placeholder when the expected file is absent, and the real image with no layout shift once the file is dropped into `public/screenshots/`.
- Edge case: page renders correctly at mobile viewport widths (this is a download page — most traffic is mobile Safari).

**Verification**: Visual review against the app's own onboarding screens for message consistency; Lighthouse/mobile-friendliness check.

---

### U3. Pricing section

**Goal**: Displays the three ChessCoach Pro plans with correct pricing, matching what's actually configured in App Store Connect/RevenueCat.

**Requirements**: R3

**Dependencies**: U1

**Files**:
- `components/sections/PricingTable.tsx`
- `content/pricing.ts`

**Approach**: Three plan cards -- Weekly $3.99, Monthly $8.00 (marked best-value or similar, matching the app's own `PaywallView` annual-badge convention), Annual $59.00. Pricing values live in `content/pricing.ts` as plain data, not hardcoded in JSX, so they're easy to keep in sync if App Store Connect pricing changes.

**Patterns to follow**: `Sources/GemmaChessCore/UI/PaywallView.swift`'s plan list and "BEST VALUE" badge treatment for consistent framing between app and website.

**Test scenarios**:
- Happy path: all three plans render with the exact prices from this plan's Requirements section.
- Test expectation for the "best value" badge: only the annual plan shows it, matching `PaywallView`'s `isAnnual` logic.

**Verification**: Manual cross-check against the live App Store Connect subscription prices (already equalized across territories per this session's earlier work) before shipping.

---

### U4. Privacy Policy + Terms of Use pages

**Goal**: Real, legally-adequate Privacy Policy and Terms of Use pages at the exact URLs the app already links to.

**Requirements**: R1

**Dependencies**: U1

**Files**:
- `app/privacy/page.tsx`
- `app/terms/page.tsx`

**Approach**: Cover, at minimum: what data ChessCoach collects (device-local game data per `SavedGameStore` -- games are NOT synced to any server per the app's own "Games are saved on this device only" copy in `Sources/GemmaChessCore/UI/RootView.swift`; the managed coach backend does process move/position data server-side for coaching responses; RevenueCat/App Store handle subscription billing), auto-renewable subscription terms (required by App Store Review Guideline 3.1.2 -- pricing, renewal, cancellation instructions), and standard contact/jurisdiction boilerplate. This is legal content, not engineering -- flag to the user that a lawyer or a reputable template service should review the final text before launch; this unit produces a complete first draft, not final legal sign-off.

**Patterns to follow**: `privacy.dc.html` and `terms.dc.html` (design handoff, KTD-6) already provide the exact page layout and section headers to use (Information we collect / How we use it / Your choices; Using ChessCoach / Subscriptions & billing / Disclaimers) with placeholder body copy explicitly marked for replacement -- fill in real text under this structure rather than inventing a new layout. `Sources/GemmaChessCore/UI/PaywallView.swift`'s existing auto-renewal disclosure text is the source of truth for what the app already tells users, so the website doesn't contradict it.

**Test scenarios**:
- Test expectation: none for page rendering (static content) -- but verify manually that the auto-renewal terms on this page match `PaywallView`'s disclosure text word-for-word in substance (both must describe the same renewal/cancellation behavior).

**Verification**: Both pages reachable at `https://chesscoach.im/privacy` and `https://chesscoach.im/terms` post-deploy; content reviewed against App Store Review Guideline 3.1.2's subscription-disclosure requirements.

---

### U5. Vercel domain configuration

**Goal**: `chesscoach.im` and `www.chesscoach.im` route to this website's Vercel deployment; `api.chesscoach.im` continues routing to `chesscoach-gateway`, unaffected.

**Requirements**: R6

**Dependencies**: U1

**Files**: None (Vercel dashboard / DNS configuration, not repo files)

**Approach**: Add `chesscoach.im` and `www.chesscoach.im` as domains on the new Vercel project, with `www` redirecting to apex (or vice versa -- pick one canonical form). Verify DNS (the domain's registrar) points the apex and `www` records at Vercel, while leaving the existing `api` subdomain record untouched.

**Test scenarios**:
- Test expectation: none -- infrastructure configuration, not application code.

**Verification**: `https://chesscoach.im` resolves to the new site; `https://api.chesscoach.im/api/coach` (or another known gateway route) still resolves to `chesscoach-gateway` unchanged, confirming no regression.

---

## Scope Boundaries

### In scope
- Everything in the Output Structure and Implementation Units above.

### Deferred to Follow-Up Work
- **Supplying the actual screenshots** (R7) — the user will provide these; this plan only builds the placeholder slots (`ScreenshotFrame` in U2) they drop into.
- **Uploading the same screenshot set to App Store Connect** — once the user supplies the assets, the same files (or same source, re-exported at App Store's required device sizes) go to both `public/screenshots/` in this repo and the App Store Connect listing. Uploading to ASC itself is a separate action (already have `asc_upload_screenshots` tooling available from earlier session work) and not part of this website plan.
- **Updating `PaywallView`'s placeholder URLs** (`Sources/GemmaChessCore/UI/PaywallView.swift`, currently `https://chesscoach.im/terms` / `https://chesscoach.im/privacy`) — these URLs are already correct as written and need no code change once U4 ships; this is a verification step (confirm the links resolve), not an implementation unit, and belongs to whoever does final App Store submission prep, not this plan.
- Swapping the App Store badge (KTD-4) from "Coming soon" to a real deep link once the app is approved and the listing is public. One-line content change in `content/pricing.ts` or `AppStoreBadge.tsx`, not worth its own unit.
- Analytics/conversion tracking, A/B testing, blog/changelog pages, App Store screenshot carousel on the landing page, localization -- none requested, all easy to add later without restructuring this plan's output.
- Final legal review/sign-off on the Privacy Policy and Terms of Use text (U4 produces a complete draft; a lawyer or template service should review before the subscription goes live).

### Outside this plan's identity
- Any changes to `chesscoach-gateway` itself -- explicitly unaffected (KTD-1, KTD-3).
- Any changes to the public GemmaChess repo -- this plan's website work happens entirely in the new private repo.
- `ChessCoach Site.dc.html` (the larger, second file in the design handoff bundle) -- the user explicitly confirmed `ChessCoach.dc.html` is the design to implement; the "Site" variant is not in scope for this plan unless the user says otherwise.

---

## Open Questions

- **Legal template source**: should the Privacy Policy/Terms of Use in U4 start from a paid template service (e.g., Termly, iubenda) or be hand-drafted from the disclosures already in `PaywallView`? Deferred to implementation -- either is fine as a first draft; flag for legal review either way.
- **Domain registrar access**: U5 assumes DNS control over `chesscoach.im` is already available (it must be, since `api.chesscoach.im` is live today) -- confirm the same account/access applies for adding the apex and `www` records.
- **Design bundle persistence**: the design handoff bundle (KTD-6) currently lives at `/tmp/chesscoach-design/chesscoach-download-website/` -- ephemeral. Before `/ce-work` starts on U1, copy `ChessCoach.dc.html`, `privacy.dc.html`, and `terms.dc.html` into the new `chesscoach-website` repo (e.g. a `design-reference/` folder, excluded from the production build) so the reference survives past this session.
