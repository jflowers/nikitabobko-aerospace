import AppKit
import Common

enum FrozenTreeNode: Sendable, Codable, Equatable {
    case container(FrozenContainer)
    case window(FrozenWindow)
}

struct FrozenContainer: Sendable, Codable, Equatable {
    let children: [FrozenTreeNode]
    let layout: Layout
    let orientation: Orientation
    let weight: CGFloat

    @MainActor init(_ container: TilingContainer) {
        children = container.children.map {
            switch $0.nodeCases {
                case .window(let w): .window(FrozenWindow(w))
                case .tilingContainer(let c): .container(FrozenContainer(c))
                case .workspace,
                     .floatingWindowsContainer,
                     .macosMinimizedWindowsContainer,
                     .macosHiddenAppsWindowsContainer,
                     .macosFullscreenWindowsContainer,
                     .macosPopupWindowsContainer:
                    illegalChildParentRelation(child: $0, parent: container)
            }
        }
        layout = container.layout
        orientation = container.orientation
        weight = getWeightOrNil(container) ?? 1
    }
}

struct FrozenFrame: Sendable, Codable, Equatable {
    let topLeftX: CGFloat
    let topLeftY: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(topLeftX: CGFloat, topLeftY: CGFloat, width: CGFloat, height: CGFloat) {
        self.topLeftX = topLeftX
        self.topLeftY = topLeftY
        self.width = width
        self.height = height
    }

    init(_ rect: Rect) {
        self.init(topLeftX: rect.topLeftX, topLeftY: rect.topLeftY, width: rect.width, height: rect.height)
    }
}

struct FrozenWindow: Sendable, Codable, Equatable {
    let id: UInt32
    let weight: CGFloat
    // Top-left origin coordinates (same convention as `Rect`); only floating windows have frames
    let frame: FrozenFrame?
    let isSticky: Bool

    @MainActor init(_ window: Window, frame: FrozenFrame? = nil) {
        id = window.windowId
        weight = getWeightOrNil(window) ?? 1
        self.frame = frame
        isSticky = window.isSticky
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UInt32.self, forKey: .id)
        weight = try container.decode(CGFloat.self, forKey: .weight)
        frame = try container.decodeIfPresent(FrozenFrame.self, forKey: .frame)
        // isSticky was added after frame; files saved by older versions don't have it
        isSticky = try container.decodeIfPresent(Bool.self, forKey: .isSticky) ?? false
    }
}

@MainActor private func getWeightOrNil(_ node: TreeNode) -> CGFloat? {
    ((node.parent as? TilingContainer)?.orientation).map { node.getWeight($0) }
}
