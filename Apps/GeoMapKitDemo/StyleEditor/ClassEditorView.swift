import FeatureStore
import MapStyle
import SwiftUI

/// The settings of one feature class: where it is shown, and how it is filled, stroked, marked and named.
struct ClassEditorView: View {
    let model: StyleEditorModel
    let featureClass: FeatureClass

    private var classStyle: ClassStyle? { model.style.classes[featureClass] }

    /// A binding to a part of the class style: it reads the part (or a fallback when the class or the part is not there) and writes
    /// through the model, so that every change shows in the preview and can be undone. Changes to one field in a row are one step to undo.
    private func field<T>(_ name: String, get: @escaping (ClassStyle) -> T?, set: @escaping (inout ClassStyle, T) -> Void, fallback: T) -> Binding<T> {
        Binding(
            get: { classStyle.flatMap(get) ?? fallback },
            set: { new in
                model.change("class.\(featureClass).\(name)") { style in
                    guard var current = style.classes[featureClass] else { return }
                    set(&current, new)
                    style.classes[featureClass] = current
                }
            })
    }

    /// A switch for a part that a class may or may not have: on makes the part from `make`, off removes it.
    private func part<T>(_ name: String, _ path: WritableKeyPath<ClassStyle, T?>, make: @escaping () -> T) -> Binding<Bool> {
        Binding(
            get: { classStyle?[keyPath: path] != nil },
            set: { on in
                model.change("class.\(featureClass).\(name).switch") { style in
                    guard var current = style.classes[featureClass] else { return }
                    current[keyPath: path] = on ? (current[keyPath: path] ?? make()) : nil
                    style.classes[featureClass] = current
                }
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Drawn in this style", isOn: Binding(
                    get: { classStyle != nil },
                    set: { on in
                        model.change("class.\(featureClass).drawn") { style in
                            // Switching a class back on restores what the saved style or the Standard style had for it.
                            style.classes[featureClass] =
                                on ? (model.saved.classes[featureClass] ?? MapStyle.standard.classes[featureClass] ?? Self.newClass) : nil
                        }
                    }))
            } footer: {
                if classStyle == nil { Text("This class is not drawn: nothing in the map is shown for it.") }
            }
            if classStyle != nil {
                visibility
                fillSection
                strokeSection
                pointSection
                labelSection
                Section {
                    Text("Bridges, tunnels, widths by number of lanes and the casing of bridges are set in the JSON editor.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Menu("Reset this class to…") {
                        Button("The Standard style") { model.resetClass(featureClass, from: .standard) }
                        Button("The Watch style") { model.resetClass(featureClass, from: .watch) }
                    }
                }
            }
        }
        .navigationTitle(ClassGroups.name(of: featureClass))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// What a class gets when it is switched on: a thin grey line, to be changed.
    private static var newClass: ClassStyle {
        ClassStyle(
            stroke: StrokeStyle(color: ZoomValue(constant: MapColor(hex: 0x888888)), width: LineWidth(points: ZoomValue(constant: 1))), layer: 20)
    }

    // MARK: Sections

    private var visibility: some View {
        Section("Where it is shown") {
            ZoomRangeEditor(
                title: "Zoom range",
                range: field("visible", get: { $0.visibleZoom }, set: { $0.visibleZoom = $1 }, fallback: 0...24))
            Stepper(
                value: field("layer", get: { $0.layer }, set: { $0.layer = $1 }, fallback: 0), in: 0...99
            ) { Text("Layer \(classStyle?.layer ?? 0)") }
            Text("A higher layer is drawn over a lower one.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var fillSection: some View {
        Section("Fill") {
            Toggle("Filled", isOn: part("fill", \.fill) { FillStyle(color: ZoomValue(constant: MapColor(hex: 0xCCCCCC))) })
            if classStyle?.fill != nil {
                ColorStopsEditor(
                    title: "Colour",
                    value: field("fill.color", get: { $0.fill?.color }, set: { $0.fill?.color = $1 }, fallback: ZoomValue(constant: .black)))
            }
        }
    }

    private var strokeSection: some View {
        Section("Line") {
            Toggle("Drawn as a line", isOn: part("stroke", \.stroke) {
                StrokeStyle(color: ZoomValue(constant: MapColor(hex: 0x888888)), width: LineWidth(points: ZoomValue(constant: 1)))
            })
            if classStyle?.stroke != nil {
                ColorStopsEditor(
                    title: "Colour",
                    value: field("stroke.color", get: { $0.stroke?.color }, set: { $0.stroke?.color = $1 }, fallback: ZoomValue(constant: .black)))
                NumberStopsEditor(
                    title: "Width (points)",
                    value: field("stroke.width", get: { $0.stroke?.width.points }, set: { $0.stroke?.width.points = $1 }, fallback: ZoomValue(constant: 1)),
                    range: 0...40, step: 0.1)
                TextField("Dashes (on off …, in points)", text: dashText)
                #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                #endif
                Picker("Ends", selection: field("stroke.cap", get: { $0.stroke?.cap }, set: { $0.stroke?.cap = $1 }, fallback: .round)) {
                    Text("Round").tag(LineCap.round); Text("Flat").tag(LineCap.butt); Text("Square").tag(LineCap.square)
                }
                Picker("Corners", selection: field("stroke.join", get: { $0.stroke?.join }, set: { $0.stroke?.join = $1 }, fallback: .round)) {
                    Text("Round").tag(LineJoin.round); Text("Sharp").tag(LineJoin.miter); Text("Bevel").tag(LineJoin.bevel)
                }
                Toggle("Casing (an outline of the line)", isOn: Binding(
                    get: { classStyle?.stroke?.casing != nil },
                    set: { on in
                        model.change("class.\(featureClass).stroke.casing.switch") { style in
                            guard var current = style.classes[featureClass], var stroke = current.stroke else { return }
                            if on {
                                stroke.casing = stroke.casing
                                    ?? StrokeStyle.Casing(color: ZoomValue(constant: MapColor(hex: 0x666666)), extraPoints: ZoomValue(constant: 1))
                            } else {
                                stroke.casing = nil
                            }
                            current.stroke = stroke
                            style.classes[featureClass] = current
                        }
                    }))
                if classStyle?.stroke?.casing != nil {
                    ColorStopsEditor(
                        title: "Casing colour",
                        value: field("stroke.casing.color", get: { $0.stroke?.casing?.color }, set: { $0.stroke?.casing?.color = $1 }, fallback: ZoomValue(constant: .black)))
                    NumberStopsEditor(
                        title: "Casing, extra width on each side (points)",
                        value: field("stroke.casing.extra", get: { $0.stroke?.casing?.extraPoints }, set: { $0.stroke?.casing?.extraPoints = $1 }, fallback: ZoomValue(constant: 1)),
                        range: 0...20, step: 0.1)
                }
            }
        }
    }

    /// The dash pattern as text ("6 3"); text that is not numbers is not applied until it is.
    private var dashText: Binding<String> {
        Binding(
            get: { (classStyle?.stroke?.dash ?? []).map { String(format: "%g", $0) }.joined(separator: " ") },
            set: { text in
                let numbers = text.split(whereSeparator: { $0 == " " || $0 == "," }).map { Double($0) }
                guard numbers.allSatisfy({ $0 != nil && $0! >= 0 && $0!.isFinite }) else { return }
                model.change("class.\(featureClass).stroke.dash") { style in
                    style.classes[featureClass]?.stroke?.dash = numbers.compactMap { $0 }
                }
            })
    }

    private var pointSection: some View {
        Section("Point") {
            Toggle("Drawn as a point", isOn: part("point", \.point) {
                PointStyle(radius: ZoomValue(constant: 3), color: ZoomValue(constant: MapColor(hex: 0x555555)))
            })
            if classStyle?.point != nil {
                NumberStopsEditor(
                    title: "Radius (points)",
                    value: field("point.radius", get: { $0.point?.radius }, set: { $0.point?.radius = $1 }, fallback: ZoomValue(constant: 3)),
                    range: 0...30, step: 0.5)
                ColorStopsEditor(
                    title: "Colour",
                    value: field("point.color", get: { $0.point?.color }, set: { $0.point?.color = $1 }, fallback: ZoomValue(constant: .black)))
                ColorPicker(
                    "Outline colour",
                    selection: Binding(
                        get: { ColorConversion.color(classStyle?.point?.outlineColor ?? .white) },
                        set: { new in model.change("class.\(featureClass).point.outline") { $0.classes[featureClass]?.point?.outlineColor = ColorConversion.mapColor(new) } }),
                    supportsOpacity: true)
                Stepper(
                    value: field("point.outlineWidth", get: { $0.point?.outlineWidth }, set: { $0.point?.outlineWidth = $1 }, fallback: 1), in: 0...10, step: 0.5
                ) { Text("Outline width \(String(format: "%g", classStyle?.point?.outlineWidth ?? 0))") }
            }
        }
    }

    private var labelSection: some View {
        Section("Name") {
            Toggle("Shows the name", isOn: part("label", \.label) {
                LabelStyle(size: ZoomValue(constant: 10), color: MapColor(hex: 0x333333))
            })
            if classStyle?.label != nil {
                NumberStopsEditor(
                    title: "Size (points)",
                    value: field("label.size", get: { $0.label?.size }, set: { $0.label?.size = $1 }, fallback: ZoomValue(constant: 10)),
                    range: 4...40, step: 0.5)
                ColorPicker(
                    "Colour",
                    selection: Binding(
                        get: { ColorConversion.color(classStyle?.label?.color ?? .black) },
                        set: { new in model.change("class.\(featureClass).label.color") { $0.classes[featureClass]?.label?.color = ColorConversion.mapColor(new) } }),
                    supportsOpacity: true)
                ColorPicker(
                    "Halo colour",
                    selection: Binding(
                        get: { ColorConversion.color(classStyle?.label?.haloColor ?? .white) },
                        set: { new in model.change("class.\(featureClass).label.halo") { $0.classes[featureClass]?.label?.haloColor = ColorConversion.mapColor(new) } }),
                    supportsOpacity: true)
                Stepper(
                    value: field("label.haloWidth", get: { $0.label?.haloWidth }, set: { $0.label?.haloWidth = $1 }, fallback: 2), in: 0...10, step: 0.5
                ) { Text("Halo width \(String(format: "%g", classStyle?.label?.haloWidth ?? 0))") }
                ZoomRangeEditor(
                    title: "Names are shown",
                    range: field("label.visible", get: { $0.label?.visibleZoom }, set: { $0.label?.visibleZoom = $1 }, fallback: 0...24))
                Stepper(
                    value: field("label.priority", get: { Double($0.label?.priority ?? 0) }, set: { $0.label?.priority = Int($1) }, fallback: 0), in: 0...100, step: 1
                ) { Text("Priority \(classStyle?.label?.priority ?? 0) (higher names are placed first)") }
                Picker("Along a line", selection: field("label.placement", get: { $0.label?.placement }, set: { $0.label?.placement = $1 }, fallback: .onLine)) {
                    Text("On the line").tag(LabelPlacement.onLine); Text("Beside the line").tag(LabelPlacement.besideLine)
                }
                Stepper(
                    value: field("label.minimumArea", get: { $0.label?.minimumArea }, set: { $0.label?.minimumArea = max($1, 0) }, fallback: 0), in: 0...100_000, step: 100
                ) { Text("Smallest area that is named: \(Int(classStyle?.label?.minimumArea ?? 0)) square points") }
            }
        }
    }
}
