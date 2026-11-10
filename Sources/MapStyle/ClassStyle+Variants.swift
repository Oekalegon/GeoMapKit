import FeatureStore

extension ClassStyle {
    /// The index of the first variant that a feature is in, or `nil` if it is in none (it has the look of the class).
    ///
    /// - Parameters:
    ///   - subclass: The subclass byte of the feature.
    ///   - featureClass: The class of the feature.
    ///   - tag: The value of a tag of the feature, or `nil`.
    public func variantIndex(subclass: UInt8, in featureClass: FeatureClass, tag: (String) -> String? = { _ in nil }) -> Int? {
        variants.firstIndex { $0.matches(subclass: subclass, in: featureClass, tag: tag) }
    }

    /// The style of a variant: this style with the properties the variant sets, and no variants of its own.
    public func applying(_ variant: StyleVariant) -> ClassStyle {
        var result = self
        result.variants = []
        if let fill = variant.fill { result.fill = fill }
        if let stroke = variant.stroke { result.stroke = stroke }
        if let point = variant.point { result.point = point }
        if let label = variant.label { result.label = label }
        if let visibleZoom = variant.visibleZoom { result.visibleZoom = visibleZoom }
        if let layer = variant.layer { result.layer = layer }
        if let casingLayer = variant.casingLayer { result.casingLayer = casingLayer }
        if let bridge = variant.bridge { result.bridge = bridge }
        if let tunnel = variant.tunnel { result.tunnel = tunnel }
        return result
    }

    /// The style for a feature: the class's own, or that of the first variant it is in.
    public func resolved(subclass: UInt8, in featureClass: FeatureClass, tag: (String) -> String? = { _ in nil }) -> ClassStyle {
        guard let index = variantIndex(subclass: subclass, in: featureClass, tag: tag) else { return self }
        return applying(variants[index])
    }

    /// The variant after an edit of its look: `effective` is what ``applying(_:)`` gave, changed by an editor. A part that is now the same as
    /// the class's own goes back to `nil` (the variant follows the class again), a part that differs is the variant's. The selectors
    /// (name, subclasses, tags) are kept.
    ///
    /// A variant cannot switch a part off, because `nil` means "the class's": a part that an editor removed from `effective` while the
    /// class has it comes out as `nil`, that is, the class's.
    public func variant(_ variant: StyleVariant, updatedFrom effective: ClassStyle) -> StyleVariant {
        var result = variant
        func part<T: Equatable>(_ own: T?, _ edited: T?) -> T? { edited == own ? nil : edited }
        result.fill = part(fill, effective.fill)
        result.stroke = part(stroke, effective.stroke)
        result.point = part(point, effective.point)
        result.label = part(label, effective.label)
        result.visibleZoom = effective.visibleZoom == visibleZoom ? nil : effective.visibleZoom
        result.layer = effective.layer == layer ? nil : effective.layer
        result.casingLayer = part(casingLayer, effective.casingLayer)
        result.bridge = part(bridge, effective.bridge)
        result.tunnel = part(tunnel, effective.tunnel)
        return result
    }
}

