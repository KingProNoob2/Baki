import SwiftUI

extension EnvironmentValues {
    /// Controls whether screens render two-pane split layouts on iPhone Duo's inner display.
    /// Set to `false` inside a parent split's secondary pane (such as `MoreScreen`) to avoid nested splits.
    @Entry var allowsDuoSplit: Bool = true
}

#if os(iOS)
/// Environment check that is `true` only on iPhone Duo's expanded inner display (or regular/regular),
/// and never `true` on any other iPhone in portrait or landscape.
struct DuoEnvironment {
    static func isInnerDisplay(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
}

/// Renders a split `ArrangementView` when iPhone Duo's inner display is expanded and `allowsDuoSplit` is enabled.
/// On all non-Duo iPhones and Duo's compact outer display / Split View, `compact` is returned unchanged.
struct DuoAdaptiveSplit<Compact: View, Primary: View, Secondary: View>: View {
    var primaryRatio: CGFloat = 0.42
    @ViewBuilder let compact: () -> Compact
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.allowsDuoSplit) private var allowsDuoSplit

    private var usesDuoSplit: Bool {
        allowsDuoSplit && DuoEnvironment.isInnerDisplay(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
    }

    var body: some View {
        if usesDuoSplit {
            if #available(iOS 27.1, *) {
                ArrangementView {
                    primary()
                        .splitArrangementLayoutRatio(primaryRatio)
                } secondary: {
                    secondary()
                }
                .arrangementViewStyle(.split)
            } else {
                compact()
            }
        } else {
            compact()
        }
    }
}

/// Positions a floating control in the bottom corner on standard iPhones identically to before,
/// and adapts its edge, spacing, and position for vertical bars and reserved regions (fold/camera) on iPhone Duo.
struct DuoFloatingOverlayModifier<FloatingContent: View>: ViewModifier {
    let isVisible: Bool
    @ViewBuilder let floatingContent: () -> FloatingContent

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isInnerDisplay: Bool {
        DuoEnvironment.isInnerDisplay(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
    }

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            DuoFloatingOverlay27_1(
                isInnerDisplay: isInnerDisplay,
                isVisible: isVisible,
                content: content,
                floatingContent: floatingContent
            )
        } else {
            content.overlay(alignment: .bottomTrailing) {
                if isVisible {
                    floatingContent()
                        .padding(.trailing, 20)
                        .padding(.bottom, 12)
                }
            }
        }
    }
}

@available(iOS 27.1, *)
private struct DuoFloatingOverlay27_1<BaseContent: View, FloatingContent: View>: View {
    let isInnerDisplay: Bool
    let isVisible: Bool
    let content: BaseContent
    let floatingContent: () -> FloatingContent

    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge

    /// Only true on iPhone Duo poses (vertical bar active or inner display expanded).
    private var isDuoContext: Bool {
        toolbarVerticalEdge != nil || isInnerDisplay
    }

    private var alignment: Alignment {
        if toolbarVerticalEdge == .leading {
            return .bottomLeading
        }
        return .bottomTrailing
    }

    var body: some View {
        if isDuoContext {
            content.overlay {
                if isVisible {
                    GeometryReader { proxy in
                        let reserved = proxy.reservedRegions(kind: .occlusion)
                            + proxy.reservedRegions(kind: .division)
                        let edgeOffset = adjustedOffsets(in: proxy.size, reserved: reserved)

                        floatingContent()
                            .padding(toolbarVerticalEdge == .leading ? .leading : .trailing, edgeOffset.horizontal)
                            .padding(.bottom, edgeOffset.bottom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                    }
                }
            }
        } else {
            // Exact original layout for all non-Duo iPhones.
            content.overlay(alignment: .bottomTrailing) {
                if isVisible {
                    floatingContent()
                        .padding(.trailing, 20)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private func adjustedOffsets(in size: CGSize, reserved: [ReservedRegion]) -> (horizontal: CGFloat, bottom: CGFloat) {
        let baseHorizontal: CGFloat = toolbarVerticalEdge != nil ? 12 : 20
        let baseBottom: CGFloat = toolbarVerticalEdge != nil ? 10 : 12
        let buttonDiameter: CGFloat = 56
        let clearance: CGFloat = 8

        var horizontal = baseHorizontal
        var bottom = baseBottom

        let isLeading = toolbarVerticalEdge == .leading
        var buttonRect = CGRect(
            x: isLeading ? horizontal : size.width - horizontal - buttonDiameter,
            y: size.height - bottom - buttonDiameter,
            width: buttonDiameter,
            height: buttonDiameter
        )

        for region in reserved where region.frame.intersects(buttonRect) {
            let upwardShift = max(0, buttonRect.maxY - region.frame.minY + clearance)
            let inwardShift: CGFloat = isLeading
                ? max(0, region.frame.maxX - buttonRect.minX + clearance)
                : max(0, buttonRect.maxX - region.frame.minX + clearance)

            if upwardShift > 0 && upwardShift <= inwardShift {
                bottom += upwardShift
                buttonRect.origin.y -= upwardShift
            } else if inwardShift > 0 {
                horizontal += inwardShift
                buttonRect.origin.x += isLeading ? inwardShift : -inwardShift
            }
        }

        return (horizontal, bottom)
    }
}
#endif

extension View {
    /// Positions a floating action button in `.bottomTrailing` on standard iPhones without any change,
    /// while adapting for vertical bars and reserved regions on iPhone Duo.
    @ViewBuilder
    func duoFloatingOverlay<FloatingContent: View>(
        isVisible: Bool = true,
        @ViewBuilder content: @escaping () -> FloatingContent
    ) -> some View {
        #if os(iOS)
        modifier(DuoFloatingOverlayModifier(isVisible: isVisible, floatingContent: content))
        #else
        self.overlay(alignment: .bottomTrailing) {
            if isVisible {
                content()
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
            }
        }
        #endif
    }

    /// Clips a nested horizontal pager to its safe-area layout bounds on iPhone Duo so adjacent
    /// pages never bleed underneath the vertical toolbar/tab bar or across a split divider.
    /// Leaves all non-Duo iPhones completely untouched.
    @ViewBuilder
    func duoClipHorizontalPager() -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            modifier(DuoHorizontalPagerClipModifier27_1())
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Prefers keeping the tab bar visible on iPhone Duo's vertical bar when vertical space is constrained.
    @ViewBuilder
    func duoPrefersTabBarCompression() -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            self.toolbarVerticalCompressionBehavior(.prefersTabBar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Prefers keeping toolbar actions visible on iPhone Duo's vertical bar for task-focused screens.
    @ViewBuilder
    func duoPrefersToolbarCompression() -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            self.toolbarVerticalCompressionBehavior(.prefersToolbarItems)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Places a sheet along a preferred edge only when expanded on iPhone Duo's inner display.
    @ViewBuilder
    func duoInnerSheetPlacement(_ placement: DuoSheetPlacement) -> some View {
        #if os(iOS)
        modifier(DuoSheetPlacementModifier(placement: placement))
        #else
        self
        #endif
    }

    /// Applies `.navigationTitle` and display mode only when shown pushed (not embedded in a Duo split detail pane).
    @ViewBuilder
    func duoDetailNavigationTitle(_ title: String, isEmbeddedInSplit: Bool, inline: Bool = true) -> some View {
        if isEmbeddedInSplit {
            self
        } else {
            self
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(inline ? .inline : .large)
        }
    }
}

enum DuoSheetPlacement {
    case leading, center, trailing
}

#if os(iOS)
@available(iOS 27.1, *)
private struct DuoHorizontalPagerClipModifier27_1: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isDuoContext: Bool {
        toolbarVerticalEdge != nil || DuoEnvironment.isInnerDisplay(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
    }

    func body(content: Content) -> some View {
        if isDuoContext {
            content
                .scrollClipDisabled(false)
                .clipShape(Rectangle())
        } else {
            content
        }
    }
}

private struct DuoSheetPlacementModifier: ViewModifier {
    let placement: DuoSheetPlacement

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        if #available(iOS 27.0, *),
           DuoEnvironment.isInnerDisplay(
               horizontalSizeClass: horizontalSizeClass,
               verticalSizeClass: verticalSizeClass
           ) {
            content.presentationPlacement(swiftUIPlacement)
        } else {
            content
        }
    }

    @available(iOS 27.0, *)
    private var swiftUIPlacement: PresentationPlacement {
        switch placement {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
#endif

extension ToolbarContent {
    /// Sets high visibility priority on iOS 27+ so essential toolbar controls stay out of the overflow menu longer.
    @ToolbarContentBuilder
    func duoHighVisibilityPriority() -> some ToolbarContent {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            self.visibilityPriority(.high)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Sets low visibility priority on iOS 27+ so secondary actions move to the overflow menu first on compact vertical bars.
    @ToolbarContentBuilder
    func duoLowVisibilityPriority() -> some ToolbarContent {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            self.visibilityPriority(.low)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
