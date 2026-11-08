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
/// Gestures: drag to pan; on iOS, iPadOS and macOS pinch to zoom and twist two fingers to turn the map; on watchOS the
/// Digital Crown zooms and a drag pans. A compass appears in the corner of a turned map, and a tap on it turns the map back
/// to north. The bearing is a binding too, so an app can set it (heading up on the Watch); the view draws a new frame when it
/// differs by more than a degree from the drawn one, so an app that follows a compass should filter it itself.
/// To show another store, give the view a new identity (`.id(...)`); a changed `style` is picked up by itself.
/// On the Mac the scroll wheel zooms about the pointer, and a two-finger scroll on a trackpad pans.
///
/// The data credit is drawn over the map, in the corner of the view, as the style's `attribution` setting says.
public struct MapView: View {
    private let file: FeatureStoreFile
    private let style: MapStyle
    @Binding private var center: Coordinate
    @Binding private var zoom: Double
    @Binding private var bearing: Double

    @State private var model: MapModel
    @State private var dragStart: MapViewport?
    @State private var pinchStart: Double?
    @State private var rotationStart: Double?
    @State private var interacting = false
    #if os(macOS)
    @State private var scrollEnd: Task<Void, Never>?
    #endif
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
        self.init(file: file, style: style, center: center, zoom: zoom, bearing: .constant(0))
    }

    /// Creates a map view that can be turned.
    ///
    /// - Parameters:
    ///   - file: The store to draw. Read-only; the view never writes.
    ///   - style: The style. Changing it draws a new image.
    ///   - center: The coordinate in the middle of the view. The view changes it when the user pans.
    ///   - zoom: The fractional zoom level (256-point tiles). The view changes it when the user zooms.
    ///   - bearing: The compass direction at the top of the view, in degrees clockwise from north (0 is north up). The view
    ///     changes it when the user turns the map; labels stay upright at every bearing.
    public init(
        file: FeatureStoreFile, style: MapStyle = .standard, center: Binding<Coordinate>, zoom: Binding<Double>,
        bearing: Binding<Double>
    ) {
        self.file = file
        self.style = style
        _center = center
        _zoom = zoom
        _bearing = bearing
        _model = State(initialValue: MapModel(file: file, style: style))
    }

    public var body: some View {
        GeometryReader { geometry in
            let viewport = MapViewport(
                center: center, zoom: zoom, width: geometry.size.width, height: geometry.size.height, bearing: bearing)
            ZStack {
                Color(style.background)
                if let frame = model.frame {
                    let plan = MapFramePlan(frame: frame.viewport, requested: viewport)
                    Image(decorative: frame.image, scale: frame.scale)
                        .resizable()
                        .frame(width: plan.width, height: plan.height)
                        .rotationEffect(.degrees(plan.rotation))
                        .position(x: plan.centre.x, y: plan.centre.y)
                } else if let message = model.errorDescription {
                    Text(message).font(.footnote).multilineTextAlignment(.center).padding()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay(alignment: .bottomTrailing) { attributionLabel }
            #if !os(watchOS)
            .overlay(alignment: .topTrailing) { compass }
            #endif
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel("Map")
            .gesture(pan(in: geometry.size))
            #if !os(watchOS)
            .gesture(pinch())
            .simultaneousGesture(rotate())
            #if os(macOS)
            .background(ScrollWheelMonitor { scroll in handle(scroll, in: geometry.size) })
            #endif
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
                let start = dragStart ?? MapViewport(center: center, zoom: zoom, width: size.width, height: size.height, bearing: bearing)
                dragStart = start
                center = Self.normalized(
                    start.coordinate(
                        at: ScreenPoint(x: size.width / 2 - value.translation.width, y: size.height / 2 - value.translation.height)))
            }
            .onEnded { _ in
                dragStart = nil
                updateInteracting()
            }
    }

    /// Keeps a panned centre valid: the latitude stays within the Web Mercator limit, and a longitude past ±180° wraps.
    static func normalized(_ coordinate: Coordinate) -> Coordinate {
        let limit = TileID.maximumLatitude
        var longitude = (coordinate.longitude + 180).truncatingRemainder(dividingBy: 360)
        if longitude < 0 { longitude += 360 }
        return Coordinate(latitude: min(max(coordinate.latitude, -limit), limit), longitude: longitude - 180)
    }

    #if os(macOS)
    /// A scroll wheel zooms about the pointer, a trackpad scroll pans. The frame is redrawn a moment after the last event.
    private func handle(_ scroll: ScrollWheelMonitor.Scroll, in size: CGSize) {
        let viewport = MapViewport(center: center, zoom: zoom, width: size.width, height: size.height, bearing: bearing)
        interacting = true
        if scroll.precise {
            center = Self.normalized(MapScroll.panned(viewport, dx: scroll.dx, dy: scroll.dy))
        } else {
            let result = MapScroll.zoomed(viewport, at: scroll.pointer, delta: scroll.dy, in: Self.zoomRange)
            center = Self.normalized(result.center)
            zoom = result.zoom
        }
        scrollEnd?.cancel()
        scrollEnd = Task {
            try? await Task.sleep(for: .milliseconds(200))
            if !Task.isCancelled { updateInteracting() }
        }
    }
    #endif

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
                updateInteracting()
            }
    }

    /// Two fingers twisting turn the map with them: the map follows the fingers, so a clockwise twist turns the map clockwise,
    /// which lowers the bearing.
    private func rotate() -> some Gesture {
        RotateGesture()
            .onChanged { value in
                interacting = true
                let start = rotationStart ?? bearing
                rotationStart = start
                bearing = Self.wrapped(start - value.rotation.degrees)
            }
            .onEnded { _ in
                rotationStart = nil
                updateInteracting()
            }
    }

    /// The compass: an arrow that points to north on the turned map. A tap turns the map back to north up.
    @ViewBuilder private var compass: some View {
        if bearing != 0 {
            Button {
                bearing = 0
            } label: {
                Image(systemName: "location.north.fill")
                    .rotationEffect(.degrees(-bearing))
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Compass")
            .accessibilityHint("Turns the map back to north up")
        }
    }
    #endif

    /// Sets `interacting` from the gestures that are still going on, so that the end of one gesture does not end the others.
    private func updateInteracting() {
        interacting = dragStart != nil || pinchStart != nil || rotationStart != nil
    }

    /// A bearing wrapped into 0..<360.
    static func wrapped(_ bearing: Double) -> Double {
        var value = bearing.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value >= 360 ? 0 : value
    }

    /// The data credit in the corner of the view, or nothing when the style hides it (the app then shows it elsewhere).
    @ViewBuilder private var attributionLabel: some View {
        if let text = style.attribution.text(for: file.attribution) {
            Text(text)
                .font(.system(size: 8))
                .foregroundStyle(Color.black.opacity(0.8))
                .padding(.horizontal, 3)
                .background(Color.white.opacity(0.7))
                .allowsHitTesting(false)
                .accessibilityLabel(file.attribution)
        }
    }
}

extension Color {
    /// The colour of a ``MapColor``.
    init(_ color: MapColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
