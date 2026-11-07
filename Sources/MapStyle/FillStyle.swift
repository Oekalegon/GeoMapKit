/// How an area is filled. Areas are filled with the even-odd rule, so holes stay empty.
public struct FillStyle: Sendable, Equatable {
    /// The fill colour. Its alpha is the fill opacity.
    public var color: ZoomValue<MapColor>

    /// Creates a fill style.
    public init(color: ZoomValue<MapColor>) {
        self.color = color
    }
}
