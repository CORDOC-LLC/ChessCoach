//  ManagedUsageView.swift
//  Token usage + estimated cost for the managed coach, per coaching call and
//  totaled over a date range the user can adjust. Pure read view over
//  chesscoach-gateway's /api/usage — no local state to keep in sync.

import SwiftUI

public struct ManagedUsageView: View {
    @State private var since: Date = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var until: Date = .now
    @State private var report: ManagedUsageReport?
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        Form {
            Section("Date range") {
                DatePicker("From", selection: $since, displayedComponents: [.date])
                DatePicker("To", selection: $until, displayedComponents: [.date])
                Button("Refresh") { Task { await load() } }
                    .disabled(isLoading)
            }

            if isLoading {
                Section { ProgressView() }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }

            if let report {
                Section("Totals for this range") {
                    LabeledContent("Input tokens", value: report.totalInputTokens.formatted())
                    LabeledContent("Output tokens", value: report.totalOutputTokens.formatted())
                    LabeledContent("Estimated cost", value: Self.costText(report.totalCostUSD))
                        .font(.body.weight(.semibold))
                }

                Section("Per move (\(report.events.count))") {
                    if report.events.isEmpty {
                        Text("No coaching calls in this range.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(report.events) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(event.createdAt, style: .date) + Text(" ") + Text(event.createdAt, style: .time)
                                Spacer()
                                Text(Self.costText(event.costUSD)).font(.callout.weight(.medium))
                            }
                            Text("\(event.model) · \(event.inputTokens) in / \(event.outputTokens) out")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Text("Estimated cost only, based on published per-provider pricing at the time this "
                    + "was built — not billing-grade. Ground truth is your chesscoach-gateway deployment; "
                    + "verify against your actual provider invoice before relying on this for real accounting.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Coach Usage")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            report = try await ManagedUsageClient.fetchReport(since: since, until: until)
        } catch let error as CoachError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func costText(_ usd: Double) -> String {
        usd < 0.01 ? String(format: "$%.5f", usd) : String(format: "$%.4f", usd)
    }
}
