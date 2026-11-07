import FeatureStore
import GeoCore
import MapRender
import MapStyle
import SwiftUI

/// A map from a feature store file, with pan and zoom.
///
/// The view draws the map into an image that is a little larger than the view and shows that image moved and scaled
/// while the user pans or zooms. A new image is drawn only when the view has moved far from the image's centre (half the
/// margin, so the next one is ready before the edge shows), when a gesture ends after the zoom changed, when the old
/// image no longer covers the view, or when the style or store changes. That
/// keeps the work, and on the Watch the battery use, bounded: nothing is redrawn on a timer.
///
/// Gestures: drag to pan; on iOS, iPadOS and macOS pinch to zoom; on watchOS the Digital Crown zooms and a drag pans.
/// To show another store, give the view a new identity (`.id(...)`); a changed `style` is picked up by itself.
/// Mouse-only Mac users cannot zoom yet (no scroll wheel or buttons); trackpad pinch works.
///
/// The data credit is drawn into the image as the style's `attribution` setting says.
public struct MapView: View {
    private let file: FeatureStoreFile
    private let style: MapStyle
    @Binding private var center: Coordinate
    @Binding private var zoom: Double

    @State private var model: MapModel
    @State private var dragStart: MapViewport?
    @State private var pinchStart: Double?
    @State private var interacting = false
    #if os(watchOS)
    @State private var crownZoom = 0.0
    #endif
    @Environment(\.displayScale) private var displayScale

    /// The lowest and highest zoom a gesture can reach.
    public static let zoomRange: ClosedRange<Double> = 2...20

    /// Creates a map view.
    ///
    /// - Parameters:
    ///   - file: The store to draw. Read-only; the view never writes.
    ///   - style: The style. Changing it draws a new image.
    ///   - center: The coordinate in the middle of the view. The view changes it when the user pans.
    ///   - zoom: The fractional zoom level (256-point tiles). The view changes it when the user zooms.
    public init(file: FeatureStoreFile, style: MapStyle = .standard, center: Binding<Coordinate>, zoom: Binding<Double>) {
        self.file = file
        self.style = style
        _center = center
        _zoom = zoom
        _model = State(initialValue: MapModel(file: file, style: style))
    }

    public var body: some View {
        GeometryReader { geometry in
            let viewport = MapViewport(center: center, zoom: zoom, width: geometry.size.width, height: geometry.size.height)
            ZStack {
                Color(style.background)
                if let frame = model.frame {
                    let plan = MapFramePlan(frame: frame.viewport, requested: viewport)
                    Image(decorative: frame.image, scale: frame.scale)
                        .resizable()
                        .frame(width: plan.width, height: plan.height)
                        .position(x: plan.centre.x, y: plan.centre.y)
                } else if let message = model.errorDescription {
                    Text(message).font(.footnote).multilineTextAlignment(.center).padding()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel("Map")
            .gesture(pan(in: geometry.size))
            #if !os(watchOS)
            .gesture(pinch())
            #else
            .focusable()
            .digitalCrownRotation(
                $crownZoom, from: 0, through: Self.zoomRange.upperBound - Self.zoomRange.lowerBound, by: 0.1,
                sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: crownZoom) { _, value in zoom = Self.zoomRange.lowerBound + value }
            .onChange(of: zoom) { _, value in
                // Keep the Crown in step when the app sets the zoom itself.
                let wanted = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound) - Self.zoomRange.lowerBound
                if abs(wanted - crownZoom) > 0.05 { crownZoom = wanted }
            }
            .onAppear { crownZoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound) - Self.zoomRange.lowerBound }
            #endif
            .onChange(of: viewport) { _, new in model.request(viewport: new, scale: displayScale, interacting: interacting) }
            .onChange(of: interacting) { _, now in
                if !now { model.request(viewport: viewport, scale: displayScale, interacting: false) }
            }
            .onChange(of: style) { _, new in
                model.update(file: file, style: new)
                model.request(viewport: viewport, scale: displayScale, interacting: false)
            }
            .task { model.request(viewport: viewport, scale: displayScale, interacting: false) }
        }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                interacting = true
                let start = dragStart ?? MapViewport(center: center, zoom: zoom, width: size.width, height: size.height)
                dragStart = start
                center = Self.normalized(
                    start.coordinate(
                        at: ScreenPoint(x: size.width / 2 - value.translation.width, y: size.height / 2 - value.translation.height)))
            }
            .onEnded { _ in
                dragStart = nil
                interacting = pinchStart != nil
            }
    }

    /// Keeps a panned centre valid: the latitude stays within the Web Mercator limit, and a longitude past ±180° wraps.
    static func normalized(_ coordinate: Coordinate) -> Coordinate {
        let limit = TileID.maximumLatitude
        var longitude = (coordinate.longitude + 180).truncatingRemainder(dividingBy: 360)
        if longitude < 0 { longitude += 360 }
        return Coordinate(latitude: min(max(coordinate.latitude, -limit), limit), longitude: longitude - 180)
    }

    #if !os(watchOS)
    private func pinch() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                interacting = true
                let start = pinchStart ?? zoom
                pinchStart = start
                zoom = min(max(start + log2(max(value.magnification, 0.01)), Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
            }
            .onEnded { _ in
                pinchStart = nil
                interacting = dragStart != nil
            }
    }
    #endif
}

extension Color {
    /// The colour of a ``MapColor``.
    init(_ color: MapColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
