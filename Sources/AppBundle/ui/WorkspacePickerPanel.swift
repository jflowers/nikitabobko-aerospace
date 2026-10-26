import AppKit
import Common
import SwiftUI

struct WorkspacePickerViewModel {
    let names: [String]
    let selectedIndex: Int
}

final class WorkspacePickerPanel: NSPanelHud {
    @MainActor static var shared: WorkspacePickerPanel = WorkspacePickerPanel()

    override private init() {
        super.init()
    }

    func update(with model: WorkspacePickerViewModel, on monitor: MonitorInfo, onSelect: @escaping (Int) -> Void) {
        contentView?.subviews.removeAll()
        let hostingView = NSHostingView(rootView: WorkspacePickerView(model: model, onSelect: onSelect))
        let panelSize = Self.panelSize(rowsCount: model.names.count)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        contentView?.addSubview(hostingView)
        setFrame(Self.centered(panelSize, on: monitor), display: true)
        orderFrontRegardless()
    }

    func closePanel() {
        contentView?.subviews.removeAll()
        close()
    }

    private static func panelSize(rowsCount: Int) -> NSSize {
        let height = WorkspacePickerView.padding * 2 +
            CGFloat(max(rowsCount, 1)) * WorkspacePickerView.rowHeight +
            CGFloat(max(rowsCount - 1, 0)) * WorkspacePickerView.rowSpacing
        return NSSize(width: WorkspacePickerView.panelWidth, height: height)
    }
}

struct WorkspacePickerView: View {
    let model: WorkspacePickerViewModel
    let onSelect: (Int) -> Void

    static let rowHeight: CGFloat = 28
    static let rowSpacing: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 10
    static let padding: CGFloat = 16
    static let panelWidth: CGFloat = 260

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: WorkspacePickerView.rowSpacing) {
            ForEach(model.names.indices, id: \.self) { index in
                row(model.names[index], isSelected: index == model.selectedIndex)
                    .onTapGesture { onSelect(index) }
            }
        }
        .padding(WorkspacePickerView.padding)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.7) : Color.white.opacity(0.85)
    }

    private var foregroundColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private func row(_ name: String, isSelected: Bool) -> some View {
        Text(name)
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: WorkspacePickerView.rowHeight)
            .padding(.horizontal, WorkspacePickerView.rowHorizontalPadding)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(foregroundColor.opacity(0.15))
                }
            }
    }
}
