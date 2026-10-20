import AppKit
import Common
import SwiftUI

struct SwitcherViewModel {
    struct Item {
        let icon: NSImage?
        let title: String
    }

    let items: [Item]
    let selectedIndex: Int
}

final class SwitcherPanel: NSPanelHud {
    @MainActor static var shared: SwitcherPanel = SwitcherPanel()

    override private init() {
        super.init()
    }

    func update(with model: SwitcherViewModel, on monitor: MonitorInfo) {
        contentView?.subviews.removeAll()
        let hostingView = NSHostingView(rootView: SwitcherView(model: model))
        let panelSize = Self.panelSize(itemsCount: model.items.count)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        contentView?.addSubview(hostingView)
        setFrame(Self.centered(panelSize, on: monitor), display: true)
        orderFrontRegardless()
    }

    func closePanel() {
        contentView?.subviews.removeAll()
        close()
    }

    private static func panelSize(itemsCount: Int) -> NSSize {
        let width = SwitcherView.padding * 2 +
            CGFloat(max(itemsCount, 1)) * SwitcherView.itemWidth +
            CGFloat(max(itemsCount - 1, 0)) * SwitcherView.itemSpacing
        return NSSize(width: width, height: SwitcherView.panelHeight)
    }

    private static func centered(_ size: NSSize, on monitor: MonitorInfo) -> NSRect {
        let screenFrame =
            NSScreen.screens.getOrNil(atIndex: monitor.monitorAppKitNsScreenScreensId - 1)?.frame
                ?? NSScreen.main?.frame
                ?? .zero
        return NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height,
        )
    }
}

struct SwitcherView: View {
    let model: SwitcherViewModel

    static let itemWidth: CGFloat = 128
    static let itemSpacing: CGFloat = 8
    static let padding: CGFloat = 16
    static let iconSize: CGFloat = 112
    static let titleSpacing: CGFloat = 8
    static let titleHeight: CGFloat = 20
    static let panelHeight: CGFloat = padding * 2 + itemWidth + titleSpacing + titleHeight

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: SwitcherView.titleSpacing) {
            HStack(spacing: SwitcherView.itemSpacing) {
                ForEach(model.items.indices, id: \.self) { index in
                    cell(model.items[index], isSelected: index == model.selectedIndex)
                }
            }
            Text(selectedTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: SwitcherView.titleHeight)
        }
        .padding(SwitcherView.padding)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var selectedTitle: String {
        model.items.getOrNil(atIndex: model.selectedIndex)?.title ?? ""
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.7) : Color.white.opacity(0.85)
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private func cell(_ item: SwitcherViewModel.Item, isSelected: Bool) -> some View {
        let icon: NSImage? = item.icon
        return Group {
            if let icon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "macwindow").resizable().aspectRatio(contentMode: .fit)
                    .padding(32)
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(width: SwitcherView.iconSize, height: SwitcherView.iconSize)
        .frame(width: SwitcherView.itemWidth, height: SwitcherView.itemWidth)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(titleColor, lineWidth: 2)
            }
        }
    }
}
