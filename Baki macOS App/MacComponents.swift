#if os(macOS)
import SwiftUI

// MARK: - Detail column plumbing

/// What the window's detail column shows. Screens in the middle column call `show` when a row is
/// selected; the shell clears it when the sidebar selection changes.
@Observable
final class MacDetailModel {
    var selectedID: String?
    var content: AnyView?
    /// Changes with every selection so the detail column starts a fresh navigation stack.
    var token = UUID()

    func show(id: String, content: AnyView) {
        selectedID = id
        self.content = content
        token = UUID()
    }

    func reset() {
        selectedID = nil
        content = nil
        token = UUID()
    }
}

/// The detail column: the selected item, or a placeholder.
struct MacDetailPane: View {
    let model: MacDetailModel

    var body: some View {
        Group {
            if let content = model.content {
                NavigationStack {
                    content
                }
                .id(model.token)
            } else {
                ContentUnavailableView("Vyberte položku", systemImage: "sidebar.right")
            }
        }
        // A toolbar item in this column makes the window toolbar split at the list/detail divider,
        // so spacers in the list column's toolbar centre its controls within that column only.
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

// MARK: - List column header

/// Large title, optional subtitle and a row of controls, pinned above a list.
struct MacScreenHeader<Controls: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var controls: Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.largeTitle.bold())
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            controls
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MacScreenHeader where Controls == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension View {
    /// Pins a screen header above a scrolling list, with the list fading softly under it. The
    /// window's own title is hidden because the header already shows it.
    func macScreen<Header: View>(title: String, @ViewBuilder header: () -> Header) -> some View {
        // safeAreaBar keeps the header readable: the list blurs and fades under it.
        safeAreaBar(edge: .top, spacing: 0) { header() }
            .navigationTitle(title)
            .toolbar(removing: .title)
    }

    /// Inset list for the list column, with a neutral (not saturated blue) selection.
    func macList() -> some View {
        listStyle(.inset)
            .tint(.gray)
    }

    /// A row that sits directly on the page: no grouped-form box and no separator.
    func macPlainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

// MARK: - Detail column building blocks

/// Grouped form used by every detail pane: system section styling, spacing and separators.
struct MacDetailForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }
}

/// Centered tile with a title and subtitle at the top of a detail pane.
struct MacHero<Tile: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var tile: Tile

    var body: some View {
        VStack(spacing: 12) {
            tile
            VStack(spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .macPlainRow()
    }
}

/// Large rounded tile with a gradient, e.g. the grade or the lesson number.
struct MacTile<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(.white)
            .frame(width: 96, height: 96)
            .background(tint.gradient, in: .rect(cornerRadius: 26, style: .continuous))
    }
}
#endif
