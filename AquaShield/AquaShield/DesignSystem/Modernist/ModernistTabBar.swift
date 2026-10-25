//
//  ModernistTabBar.swift
//  AquaShield
//
//  Five flat slots: Home, Water, Scan (a filled square in the middle), Help, Learn. The selected tab is ink
//  and semibold; the rest are muted. Scan opens the scanner instead of a tab.
//

import SwiftUI

struct ModernistTabBar: View {
    @Binding var selection: AppTab
    var homeBadge: Int = 0
    let onScan: () -> Void

    private struct Item {
        let tab: AppTab?
        let label: String
        let symbol: String
        let id: String
    }

    private var items: [Item] {
        [Item(tab: .home, label: String(localized: "Home"), symbol: "house", id: "tab.home"),
         Item(tab: .myWater, label: String(localized: "Water"), symbol: "drop", id: "tab.water"),
         Item(tab: nil, label: String(localized: "Scan"), symbol: "viewfinder", id: "tab.scan"),
         Item(tab: .help, label: String(localized: "Help"), symbol: "lifepreserver", id: "tab.help"),
         Item(tab: .learn, label: String(localized: "Learn"), symbol: "book", id: "tab.learn")]
    }

    var body: some View {
        VStack(spacing: 0) {
            M.Rule()
            HStack(alignment: .top, spacing: 0) {
                ForEach(items, id: \.id) { item in
                    let isScan = item.tab == nil
                    let on = item.tab == selection
                    Button {
                        if let tab = item.tab {
                            if tab != selection { DS.Haptics.selection() }
                            selection = tab
                        } else {
                            onScan()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.symbol)
                                .font(.system(.body, weight: .light))
                                .foregroundStyle(isScan ? M.Colors.surface : (on ? M.Colors.ink : M.Colors.muted))
                                .frame(width: 34, height: 26)
                                .background(isScan ? M.Colors.ink : .clear)
                                .overlay(alignment: .topTrailing) {
                                    if item.tab == .home && homeBadge > 0 {
                                        M.Dot(color: M.Colors.over, size: 7).offset(x: 2, y: -1)
                                    }
                                }
                            Text(item.label)
                                .font(.system(.caption2, weight: on || isScan ? .semibold : .regular))
                                .foregroundStyle(on || isScan ? M.Colors.ink : M.Colors.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(item.label))
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier(item.id)
                }
            }
            .padding(.top, 8)
        }
        .background(M.Colors.tabBar.ignoresSafeArea(edges: .bottom))
    }
}
