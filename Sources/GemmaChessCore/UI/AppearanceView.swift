//  AppearanceView.swift
//  The "Living Themes" Appearance sheet: a picker grid of presets + the
//  user's custom themes, and a live editor for creating/editing a custom
//  theme. Mode is derived from `themeStore.draft` (non-nil = editor) so this
//  view never duplicates ThemeStore's own state.

import SwiftUI

public struct AppearanceView: View {
    @Environment(ThemeStore.self) private var themeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if themeStore.draft != nil {
                    editor
                } else {
                    picker
                }
            }
            .navigationTitle(themeStore.draft == nil ? "Appearance"
                : (themeStore.isEditingExistingCustom ? "Edit theme" : "New theme"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if themeStore.draft != nil {
                    ToolbarItem(placement: .topBarLeadingCompat) {
                        Button("Cancel") { themeStore.cancelEdit() }
                    }
                    ToolbarItem(placement: .topBarTrailingCompat) {
                        Button("Save") { themeStore.save(themeStore.draft!) }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailingCompat) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.82)])
        .presentationCornerRadius(28)
    }

    // MARK: - Picker mode

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("YOUR ROOMS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(themeStore.active.textColor.opacity(0.45))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(themeStore.allThemes) { theme in
                        themeCard(theme)
                    }
                }

                Button {
                    themeStore.newDraft(from: themeStore.active)
                } label: {
                    Label("Create a new theme", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .foregroundStyle(themeStore.active.accentColor)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(themeStore.active.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                )

                Text("Your themes are saved on this device.")
                    .font(.system(size: 11))
                    .foregroundStyle(themeStore.active.textColor.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(16)
        }
        .confirmationDialog(
            "Delete this theme? This can't be undone.",
            isPresented: Binding(
                get: { showDeleteConfirm != nil },
                set: { if !$0 { showDeleteConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = showDeleteConfirm { themeStore.delete(id: id) }
                showDeleteConfirm = nil
            }
        }
    }

    private func themeCard(_ theme: Theme) -> some View {
        let isActive = theme.id == themeStore.activeID
        return VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                theme.bgColor
                HStack(spacing: 4) {
                    Circle().fill(theme.accentColor).frame(width: 12, height: 12)
                    Circle().fill(theme.accent2Color).frame(width: 12, height: 12)
                }
                .padding(8)
                miniBoard(theme)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.onAccentColor, theme.accentColor)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .frame(height: 74)

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(theme.textColor)
                    Text(theme.type.label)
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textColor.opacity(0.45))
                }
                Spacer(minLength: 4)
                Button { themeStore.editDraft(id: theme.id) } label: {
                    Image(systemName: "pencil").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textColor.opacity(0.6))
                if theme.kind == .custom {
                    Button { showDeleteConfirm = theme.id } label: {
                        Image(systemName: "trash").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.75))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(theme.surfaceColor.opacity(0.88))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? theme.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture { themeStore.apply(id: theme.id) }
    }

    /// A tiny 2x2 checkerboard preview -- cheap to render inline in a grid of
    /// cards, unlike a full `ChessBoardView`.
    private func miniBoard(_ theme: Theme) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                theme.boardLightColor.frame(width: 22, height: 22)
                theme.boardDarkColor.frame(width: 22, height: 22)
            }
            GridRow {
                theme.boardDarkColor.frame(width: 22, height: 22)
                theme.boardLightColor.frame(width: 22, height: 22)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 4)
    }

    // MARK: - Editor mode

    @ViewBuilder
    private var editor: some View {
        if let draft = themeStore.draft {
            Form {
                Section {
                    editorPreview(draft)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Theme name", text: nameBinding)
                }

                Section("Type personality") {
                    Picker("Type", selection: typeBinding) {
                        ForEach(Theme.TypePersonality.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Colors") {
                    ForEach(Theme.ColorToken.allCases) { token in
                        colorRow(token, draft: draft)
                    }
                }

                if themeStore.isEditingExistingCustom {
                    Section {
                        Button(role: .destructive) {
                            themeStore.delete(id: draft.id)
                        } label: {
                            Text("Delete theme")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func editorPreview(_ draft: Theme) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                miniBoard8x8(draft)
                VStack(alignment: .leading, spacing: 8) {
                    Text("ChessCoach")
                        .font(draft.type.displayFont(size: 20))
                        .foregroundStyle(draft.textColor)
                    Text("Play a game")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(draft.onAccentColor)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(draft.accentColor))
                    Text("HIGHLIGHT · HINTS")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(draft.accent2Color)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            ZStack { draft.bgColor; draft.backgroundGradient }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(draft.accent2Color.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func miniBoard8x8(_ theme: Theme) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<8) { row in
                GridRow {
                    ForEach(0..<8) { col in
                        ((row + col) % 2 == 0 ? theme.boardLightColor : theme.boardDarkColor)
                            .frame(width: 12, height: 12)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(width: 96, height: 96)
    }

    private func colorRow(_ token: Theme.ColorToken, draft: Theme) -> some View {
        HStack(spacing: 12) {
            ColorPicker("", selection: colorBinding(for: token))
                .labelsHidden()
                .frame(width: 42, height: 30)
            Text(token.label)
                .font(.subheadline)
                .frame(width: 110, alignment: .leading)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                ForEach(Theme.swatches[token] ?? [], id: \.self) { hex in
                    swatch(hex, token: token, draft: draft)
                }
            }
        }
    }

    private func swatch(_ hex: String, token: Theme.ColorToken, draft: Theme) -> some View {
        let isActive = draft[token].lowercased() == hex.lowercased()
        return Circle()
            .fill(Color(hex: hex))
            .frame(width: 20, height: 20)
            .overlay(
                Circle().stroke(isActive ? draft.accentColor : draft.textColor.opacity(0.15),
                                lineWidth: isActive ? 2 : 1)
            )
            .onTapGesture {
                var updated = themeStore.draft ?? draft
                updated[token] = hex
                themeStore.draft = updated
            }
    }

    // MARK: - Bindings into the draft

    private var nameBinding: Binding<String> {
        Binding(
            get: { themeStore.draft?.name ?? "" },
            set: { if var d = themeStore.draft { d.name = $0; themeStore.draft = d } }
        )
    }

    private var typeBinding: Binding<Theme.TypePersonality> {
        Binding(
            get: { themeStore.draft?.type ?? .elegant },
            set: { if var d = themeStore.draft { d.type = $0; themeStore.draft = d } }
        )
    }

    private func colorBinding(for token: Theme.ColorToken) -> Binding<Color> {
        Binding(
            get: { Color(hex: themeStore.draft?[token] ?? "#000000") },
            set: { newColor in
                guard var d = themeStore.draft else { return }
                d[token] = newColor.toHex()
                themeStore.draft = d
            }
        )
    }
}

private extension Color {
    /// Round-trips a SwiftUI `Color` back to a `#RRGGBB` hex string, for
    /// persisting a native `ColorPicker`'s selection into `Theme`.
    func toHex() -> String {
        #if canImport(UIKit)
        let components = UIColor(self).cgColor.components ?? [0, 0, 0]
        #elseif canImport(AppKit)
        let components = (NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor.black).cgColor.components ?? [0, 0, 0]
        #endif
        let r = Int((components.count > 0 ? components[0] : 0) * 255)
        let g = Int((components.count > 1 ? components[1] : 0) * 255)
        let b = Int((components.count > 2 ? components[2] : 0) * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
