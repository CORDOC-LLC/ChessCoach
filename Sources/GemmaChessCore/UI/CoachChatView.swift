//  CoachChatView.swift
//  The on-device coach panel. When no backend is available it degrades to a single
//  line ("Engine review only — …") and hides the input. Otherwise it shows a chat
//  transcript, an input row, a "Coach summary" action, and a personalization toggle.

import SwiftUI

public struct CoachChatView: View {
    @Bindable var vm: ReviewViewModel
    @State private var draft: String = ""

    public init(vm: ReviewViewModel) { self.vm = vm }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch vm.coachAvailability {
            case .unavailable(let reason):
                Label("Engine review only — \(reason)", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .foundationModels, .gemma, .gemini, .managed:
                coachBody
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack {
            Label("Coach", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)
            Spacer()
            Toggle("Personalize", isOn: $vm.personalize)
                .toggleStyle(.switch)
                .font(.caption)
                .fixedSize()
        }
    }

    @ViewBuilder private var coachBody: some View {
        if let summary = vm.summaryText {
            VStack(alignment: .leading, spacing: 4) {
                Text("Game summary").font(.subheadline).fontWeight(.semibold)
                Text(summary.asCoachMarkdown).font(.footnote)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }

        ForEach(Array(vm.chat.enumerated()), id: \.offset) { _, message in
            HStack {
                if message.role == "user" { Spacer(minLength: 24) }
                Text(message.role == "user" ? AttributedString(message.text) : message.text.asCoachMarkdown)
                    .font(.footnote)
                    .padding(8)
                    .background(
                        (message.role == "user" ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.15)),
                        in: RoundedRectangle(cornerRadius: 8))
                if message.role != "user" { Spacer(minLength: 24) }
            }
        }

        HStack(spacing: 8) {
            TextField("Ask about this position…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            Button(action: send) {
                if vm.isAsking { ProgressView() } else { Image(systemName: "arrow.up.circle.fill") }
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.isAsking)
        }

        Button {
            Task { await vm.summarize() }
        } label: {
            if vm.isSummarizing {
                ProgressView()
            } else {
                Label("Coach summary", systemImage: "text.alignleft")
            }
        }
        .disabled(vm.session == nil || vm.isSummarizing)
        .font(.footnote)
    }

    private func send() {
        let q = draft
        draft = ""
        Task { await vm.ask(q) }
    }
}
