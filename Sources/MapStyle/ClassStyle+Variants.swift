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
}
