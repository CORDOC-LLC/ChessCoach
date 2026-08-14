//  ReviewUnlockPaywallView.swift
//  Native, theme-driven purchase screen for the "Review" plan -- a one-time,
//  non-consumable purchase (mechanically a lifetime unlock) that removes the
//  free tier's move-6 cap on Review, separate from ChessCoach Pro (see
//  PaywallView). Deliberately its own view, not an extended PaywallView:
//  different messaging (one-time vs. subscription), no auto-renewal legal
//  disclosure, and a different entry point (Review's locked content /
//  Settings, not the Pro upsell surfaces).

import SwiftUI
import RevenueCat

public struct ReviewUnlockPaywallView: View {
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.dismiss) private var dismiss

    @State private var store = ProEntitlementStore.shared
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    public init() {}

    private var theme: Theme { themeStore.effective }

    private var lifetimePackage: Package? {
        store.offerings?.current?.availablePackages.first { $0.packageType == .lifetime }
    }

    public var body: some View {
        ZStack {
            theme.bgColor.ignoresSafeArea()
            theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    featureList
                    proIncludedNote
                    packageSection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                    restoreButton
                    legalFooter
                }
                .padding(20)
                .padding(.top, 12)
            }

            closeButton
        }
        .task {
            await store.loadOfferings()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(theme.accentColor)
            Text("Review Plan")
                .font(.title.weight(.bold))
                .foregroundStyle(theme.textColor)
            Text("One-time purchase. Unlock full move analysis beyond move 6 -- once, yours forever.")
                .font(.subheadline)
                .foregroundStyle(theme.mutedTextColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 32)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            featureRow(icon: "checkmark.seal.fill", text: "Full move-by-move classification and best-move suggestions, beyond move 6")
            featureRow(icon: "infinity", text: "Every game you've played or ever will -- no subscription")
            featureRow(icon: "creditcard.fill", text: "Pay once, own it forever")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.cardBackgroundColor)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Reassurance for a Pro subscriber who lands here (e.g. via a stale-state
    /// edge case, not the normal flow -- Pro users don't see the CoachSettingsView
    /// entry point's purchase button, and ReviewScreen's lock banner never shows
    /// when they already have full access). Rendered unconditionally, OUTSIDE
    /// `packageSection`'s tri-state loading/loaded/unavailable ViewBuilder, so it
    /// never disappears during the loading spinner or the "not available" fallback.
    private var proIncludedNote: some View {
        Text("Already a Pro subscriber? You already have full Review access included.")
            .font(.caption)
            .foregroundStyle(theme.mutedTextColor)
            .multilineTextAlignment(.center)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(theme.accent2Color)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(theme.textColor)
        }
    }

    @ViewBuilder
    private var packageSection: some View {
        if store.isLoadingOfferings {
            ProgressView().tint(theme.accentColor).padding(.top, 24)
        } else if let package = lifetimePackage {
            VStack(spacing: 10) {
                HStack {
                    Text("Review Plan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textColor)
                    Spacer()
                    Text(package.storeProduct.localizedPriceString)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(theme.textColor)
                }
                .padding(14)
                .background(theme.cardBackgroundColor)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                continueButton(package)
            }
        } else {
            Text("Not available right now, try again shortly.")
                .font(.footnote)
                .foregroundStyle(theme.mutedTextColor)
                .multilineTextAlignment(.center)
                .padding(.top, 24)
        }
    }

    private func continueButton(_ package: Package) -> some View {
        Button {
            purchase(package)
        } label: {
            HStack {
                if isPurchasing { ProgressView().tint(theme.onAccentColor) }
                Text(isPurchasing ? "Processing..." : "Unlock Full Review")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(theme.onAccentColor)
            .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isPurchasing)
        .padding(.top, 4)
    }

    private var restoreButton: some View {
        Button {
            restore()
        } label: {
            if isRestoring {
                ProgressView().tint(theme.mutedTextColor)
            } else {
                Text("Restore Purchases")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.mutedTextColor)
            }
        }
        .disabled(isRestoring)
    }

    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text("Your purchase helps us keep building free features for everyone.")
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.mutedTextColor)
                .multilineTextAlignment(.center)
            Text("One-time purchase. No subscription, no renewal. Payment is charged to your Apple ID "
                + "at confirmation of purchase.")
                .font(.caption2)
                .foregroundStyle(theme.faintTextColor)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://chesscoach.im/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://chesscoach.im/privacy")!)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(theme.accent2Color)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.textColor)
                        .padding(10)
                        .background(theme.cardBackgroundColor, in: Circle())
                }
                .padding(16)
            }
            Spacer()
        }
    }

    private func purchase(_ package: Package) {
        errorMessage = nil
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                try await store.purchase(package)
                if store.hasLifetimeReviewUnlock { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        errorMessage = nil
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                try await store.restore()
                if store.hasLifetimeReviewUnlock { dismiss() }
                else { errorMessage = "No lifetime purchase found for this Apple ID." }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
