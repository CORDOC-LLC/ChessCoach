//  PaywallView.swift
//  Native, theme-driven paywall for ChessCoach Pro. Presented whenever App
//  Store production (or a channel that offers the managed backend) needs an
//  active "pro" entitlement -- see `ProEntitlementStore` for the RevenueCat
//  wrapper this reads from. A custom view rather than RevenueCatUI's template
//  paywall, so it matches Living Themes instead of introducing a second
//  visual language.

import SwiftUI
import RevenueCat

public struct PaywallView: View {
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.dismiss) private var dismiss

    @State private var store = ProEntitlementStore.shared
    @State private var selected: Package?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    public init() {}

    private var theme: Theme { themeStore.effective }

    private var packages: [Package] {
        guard let offering = store.offerings?.current else { return [] }
        return offering.availablePackages
    }

    public var body: some View {
        ZStack {
            theme.bgColor.ignoresSafeArea()
            theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    featureList
                    if store.isLoadingOfferings {
                        ProgressView().tint(theme.accentColor).padding(.top, 24)
                    } else if packages.isEmpty {
                        Text("Plans aren't available right now. Try again in a moment.")
                            .font(.footnote)
                            .foregroundStyle(theme.mutedTextColor)
                            .multilineTextAlignment(.center)
                            .padding(.top, 24)
                    } else {
                        planList
                        continueButton
                    }
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
            selected = packages.first { $0.packageType == .annual } ?? packages.first
        }
        .onChange(of: packages.count) { _, _ in
            if selected == nil {
                selected = packages.first { $0.packageType == .annual } ?? packages.first
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 40))
                .foregroundStyle(theme.accentColor)
            Text("ChessCoach Pro")
                .font(.title.weight(.bold))
                .foregroundStyle(theme.textColor)
            Text("Written coaching on every move -- grounded in the same Stockfish analysis, explained in plain English.")
                .font(.subheadline)
                .foregroundStyle(theme.mutedTextColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 32)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            featureRow(icon: "text.bubble.fill", text: "Written analysis after every move")
            featureRow(icon: "flag.checkered", text: "End-of-game summaries with patterns to work on")
            featureRow(icon: "bolt.fill", text: "No API key, no setup -- works immediately")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.cardBackgroundColor)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.cardBorderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private var planList: some View {
        VStack(spacing: 10) {
            ForEach(packages, id: \.identifier) { package in
                planRow(package)
            }
        }
    }

    private func planRow(_ package: Package) -> some View {
        let isSelected = selected?.identifier == package.identifier
        let isAnnual = package.packageType == .annual
        return Button {
            selected = package
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(planTitle(for: package))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textColor)
                        if isAnnual {
                            Text("BEST VALUE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(theme.onAccentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.accentColor, in: Capsule())
                        }
                    }
                    Text(package.storeProduct.subscriptionPeriod.map(periodLabel) ?? "")
                        .font(.caption)
                        .foregroundStyle(theme.mutedTextColor)
                }
                Spacer()
                Text(package.storeProduct.localizedPriceString)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textColor)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? theme.accentColor : theme.faintTextColor)
            }
            .padding(14)
            .background(isSelected ? theme.accentColor.opacity(0.12) : theme.cardBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? theme.accentColor : theme.cardBorderColor, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func planTitle(for package: Package) -> String {
        switch package.packageType {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        default: return package.storeProduct.localizedTitle
        }
    }

    private func periodLabel(_ period: SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: return period.value == 1 ? "Billed daily" : "Billed every \(period.value) days"
        case .week: return period.value == 1 ? "Billed weekly" : "Billed every \(period.value) weeks"
        case .month: return period.value == 1 ? "Billed monthly" : "Billed every \(period.value) months"
        case .year: return period.value == 1 ? "Billed annually" : "Billed every \(period.value) years"
        @unknown default: return ""
        }
    }

    private var continueButton: some View {
        Button {
            purchase()
        } label: {
            HStack {
                if isPurchasing { ProgressView().tint(theme.onAccentColor) }
                Text(isPurchasing ? "Processing..." : "Continue")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(theme.onAccentColor)
            .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(selected == nil || isPurchasing)
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
            Text("Subscriptions auto-renew until canceled. Manage or cancel anytime in your device's "
                + "Settings > Apple ID > Subscriptions. Payment is charged to your Apple ID at "
                + "confirmation of purchase.")
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

    private func purchase() {
        guard let selected else { return }
        errorMessage = nil
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                try await store.purchase(selected)
                if store.isProActive { dismiss() }
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
                if store.isProActive { dismiss() }
                else { errorMessage = "No active subscription found for this Apple ID." }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
