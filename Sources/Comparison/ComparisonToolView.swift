import SwiftUI

/// A single tool in the comparison panel's sidebar — one instance per tool. It owns the
/// tool's icon, the help popover it shows on hover, and the action it performs.
struct ComparisonToolView: View {
    /// Names the tool for accessibility; the button itself shows only the icon.
    let title: String
    let icon: String
    /// Explains the tool in a popover after a short hover.
    let help: String
    /// Non-nil only for tools that toggle a mode, which tint themselves while active.
    var isActive: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle)
        .frame(maxWidth: 64)
        .aspectRatio(1, contentMode: .fit)
        .tint(tint)
        .overlay {
            if isActive == true {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .hoverHelp(help)
    }

    /// Modal tools go accented while active and dim while idle; plain tools keep the default tint.
    private var tint: Color? {
        guard let isActive else { return nil }
        return isActive ? .accentColor : .secondary
    }
}

/// Shows a helper popover after hovering over a view for 3 seconds.
private struct HoverHelp: ViewModifier {
    let text: String
    @State private var showHelp = false
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                task?.cancel()
                if inside {
                    task = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if !Task.isCancelled { showHelp = true }
                    }
                } else {
                    showHelp = false
                }
            }
            .popover(isPresented: $showHelp, arrowEdge: .trailing) {
                Text(text)
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: 260)
            }
    }
}

private extension View {
    func hoverHelp(_ text: String) -> some View {
        modifier(HoverHelp(text: text))
    }
}

#Preview {
    HStack {
        ComparisonToolView(
            title: "Add Ruler",
            icon: "ruler",
            help: "Adds a cyan horizontal guide line. Drag it up or down, or click the red ✕ to delete it.",
            action: { }
        )
        .padding(24)

        ComparisonToolView(
            title: "Add Ruler",
            icon: "ruler",
            help: "Adds a cyan horizontal guide line. Drag it up or down, or click the red ✕ to delete it.",
            isActive: true,
            action: { }
        )
        .padding(24)

    }
}
