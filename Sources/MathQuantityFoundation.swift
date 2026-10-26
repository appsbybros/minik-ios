import Foundation

struct MathObjectThemeID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A Math object theme identifier cannot be empty.")
        self.rawValue = rawValue
    }
}

struct MathObjectAsset: Hashable, Sendable {
    let assetName: String
    let accessibilityLabel: String

    init(assetName: String, accessibilityLabel: String) {
        precondition(!assetName.isEmpty, "A Math object asset name cannot be empty.")
        precondition(!accessibilityLabel.isEmpty, "A Math object accessibility label cannot be empty.")
        self.assetName = assetName
        self.accessibilityLabel = accessibilityLabel
    }
}

struct MathObjectTheme: Hashable, Sendable {
    let id: MathObjectThemeID
    let objects: [MathObjectAsset]
    let emptyStateAsset: MathObjectAsset?

    init?(id: MathObjectThemeID, objects: [MathObjectAsset], emptyStateAsset: MathObjectAsset?) {
        guard !objects.isEmpty else { return nil }
        self.id = id
        self.objects = objects
        self.emptyStateAsset = emptyStateAsset
    }

    func object(forItemAt index: Int) -> MathObjectAsset {
        objects[index % objects.count]
    }
}

struct MathObjectThemeManifest: Sendable {
    private let themesByID: [MathObjectThemeID: MathObjectTheme]

    init?(themes: [MathObjectTheme]) {
        guard Set(themes.map(\.id)).count == themes.count else { return nil }
        let indexed = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, $0) })
        themesByID = indexed
    }

    func theme(for id: MathObjectThemeID) -> MathObjectTheme? {
        themesByID[id]
    }
}

enum MathQuantityLayoutMode: Hashable, Sendable {
    case individual
    case grouped(groupCounts: [Int])
}

struct MathQuantityLayoutItem: Hashable, Sendable {
    let itemIndex: Int
    let groupIndex: Int?
    let centerX: Double
    let centerY: Double
    let diameter: Double
}

struct MathQuantityLayoutResult: Hashable, Sendable {
    let items: [MathQuantityLayoutItem]
}

struct MathQuantityLayout: Hashable, Sendable {
    let maximumRenderedItems: Int
    let minimumItemDiameter: Double
    let itemSpacing: Double
    let groupSpacing: Double

    init(
        maximumRenderedItems: Int = 30,
        minimumItemDiameter: Double = 18,
        itemSpacing: Double = 8,
        groupSpacing: Double = 16
    ) {
        precondition(maximumRenderedItems > 0)
        precondition(minimumItemDiameter > 0)
        precondition(itemSpacing >= 0)
        precondition(groupSpacing >= 0)
        self.maximumRenderedItems = maximumRenderedItems
        self.minimumItemDiameter = minimumItemDiameter
        self.itemSpacing = itemSpacing
        self.groupSpacing = groupSpacing
    }

    func layout(
        count: Int,
        inWidth width: Double,
        height: Double,
        mode: MathQuantityLayoutMode
    ) -> MathQuantityLayoutResult? {
        guard count >= 0,
              count <= maximumRenderedItems,
              width > 0,
              height > 0 else { return nil }
        guard count > 0 else { return MathQuantityLayoutResult(items: []) }

        switch mode {
        case .individual:
            return grid(count: count, width: width, height: height, offsetX: 0, groupIndex: nil, startIndex: 0)
        case .grouped(let groupCounts):
            guard !groupCounts.isEmpty,
                  groupCounts.allSatisfy({ $0 > 0 }),
                  groupCounts.reduce(0, +) == count else { return nil }
            let availableWidth = width - (Double(groupCounts.count - 1) * groupSpacing)
            guard availableWidth > 0 else { return nil }
            let groupWidth = availableWidth / Double(groupCounts.count)
            var startIndex = 0
            var items: [MathQuantityLayoutItem] = []
            for (groupIndex, groupCount) in groupCounts.enumerated() {
                let offsetX = Double(groupIndex) * (groupWidth + groupSpacing)
                guard let group = grid(
                    count: groupCount,
                    width: groupWidth,
                    height: height,
                    offsetX: offsetX,
                    groupIndex: groupIndex,
                    startIndex: startIndex
                ) else { return nil }
                items.append(contentsOf: group.items)
                startIndex += groupCount
            }
            return MathQuantityLayoutResult(items: items)
        }
    }

    private func grid(
        count: Int,
        width: Double,
        height: Double,
        offsetX: Double,
        groupIndex: Int?,
        startIndex: Int
    ) -> MathQuantityLayoutResult? {
        // Android Minik Math Plus countingGrid (ab3e427): every object stays inside its card.
        // A card too small for the preferred minimum still shows all of them, smaller, rather
        // than none at all.
        var best: (columns: Int, rows: Int, diameter: Double)?
        var smallerBest: (columns: Int, rows: Int, diameter: Double)?
        for columns in 1...count {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let horizontal = (width - Double(columns - 1) * itemSpacing) / Double(columns)
            let vertical = (height - Double(rows - 1) * itemSpacing) / Double(rows)
            let diameter = min(horizontal, vertical)
            if diameter >= minimumItemDiameter, diameter > (best?.diameter ?? 0) {
                best = (columns, rows, diameter)
            }
            if diameter > 0, diameter > (smallerBest?.diameter ?? 0) {
                smallerBest = (columns, rows, diameter)
            }
        }
        guard let best = best ?? smallerBest else { return nil }

        let occupiedWidth = Double(best.columns) * best.diameter + Double(best.columns - 1) * itemSpacing
        let occupiedHeight = Double(best.rows) * best.diameter + Double(best.rows - 1) * itemSpacing
        let originX = offsetX + (width - occupiedWidth) / 2
        let originY = (height - occupiedHeight) / 2
        let items = (0..<count).map { localIndex in
            let column = localIndex % best.columns
            let row = localIndex / best.columns
            return MathQuantityLayoutItem(
                itemIndex: startIndex + localIndex,
                groupIndex: groupIndex,
                centerX: originX + best.diameter / 2 + Double(column) * (best.diameter + itemSpacing),
                centerY: originY + best.diameter / 2 + Double(row) * (best.diameter + itemSpacing),
                diameter: best.diameter
            )
        }
        return MathQuantityLayoutResult(items: items)
    }
}
