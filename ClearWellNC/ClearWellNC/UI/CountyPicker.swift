//
//  CountyPicker.swift
//  ClearWellNC
//
//  Search box plus a tappable list of NC counties. Replaces the 100-row wheel in onboarding and Risk Check.
//

import SwiftUI

struct CountyPicker: View {
    @Binding var selection: String?
    /// The "no county" choice ("Not sure", "Choose later").
    let noneLabel: String

    @State private var query = ""

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return CountyNames.all }
        return CountyNames.all.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DS.Colors.textSecondary)
                    .accessibilityHidden(true)
                TextField("Search counties", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            .font(DS.Typography.body)
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: DS.Size.largeTapTarget)
            .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous).strokeBorder(DS.Colors.separator))

            LazyVStack(spacing: 0) {
                if query.isEmpty {
                    row(title: noneLabel, value: nil)
                }
                ForEach(matches, id: \.self) { name in
                    row(title: String(localized: "\(name) County"), value: name)
                }
                if matches.isEmpty {
                    Text("No county matches \"\(query)\"")
                        .font(DS.Typography.subheadline)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: DS.Size.largeTapTarget)
                }
            }
            .dsCard(padding: DS.Space.xs)
        }
    }

    private func row(title: String, value: String?) -> some View {
        let isSelected = selection == value
        return Button {
            DS.Haptics.selection()
            selection = value
        } label: {
            HStack {
                Text(title)
                    .font(isSelected ? DS.Typography.headline : DS.Typography.body)
                    .foregroundStyle(DS.Colors.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Colors.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DS.Space.m)
            .frame(minHeight: DS.Size.tapTarget + 4)
            .background(isSelected ? DS.Colors.accentSoft : .clear,
                        in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(isSelected ? Text("Selected") : Text(""))
    }
}

#Preview("Light") {
    CountyPicker(selection: .constant("Wake"), noneLabel: "Not sure").dsPreview(.light)
}

#Preview("Dark") {
    CountyPicker(selection: .constant(nil), noneLabel: "Not sure").dsPreview(.dark)
}

#Preview("Largest text") {
    CountyPicker(selection: .constant("Wake"), noneLabel: "Not sure").dsPreview(.largestText)
}
