import FeatureStore
import Foundation
import MapStyle
import SwiftUI
import Testing

@testable import GeoMapKitDemo

@Suite("Zoom stops")
struct ZoomValueEditingTests {
    private let value = ZoomValue<Double>((8, 1), (12, 2))

    @Test func aStopIsAddedAfterTheLastAndTheLastOneIsNeverRemoved() {
        let more = value.addingStop()
        #expect(more.stops.map(\.zoom) == [8, 12, 14] && more.stops.last?.value == 2)
        // At the top of the range it stays at 24.
        let top = ZoomValue<Double>((23, 1)).addingStop().addingStop()
        #expect(top.stops.map(\.zoom) == [23, 24])
        #expect(value.removingStop(at: 0).stops.map(\.zoom) == [12])
        #expect(value.removingStop(at: 0).removingStop(at: 0).stops.count == 1, "a value needs a stop")
        #expect(value.removingStop(at: 9) == value, "no such stop")
    }

    @Test func movingAStopKeepsTheStopsSortedAndReplacesOneAtTheSameZoom() {
        #expect(value.settingZoom(14, at: 0).stops.map(\.zoom) == [12, 14])
        #expect(value.settingZoom(12, at: 0).stops.count == 1, "onto the zoom of another stop")
        #expect(value.settingZoom(40, at: 1).stops.last?.zoom == 24 && value.settingZoom(-3, at: 0).stops.first?.zoom == 0)
        #expect(value.settingZoom(.nan, at: 0) == value)
    }

    @Test func aValueCanBeSetAndMadeConstant() {
        #expect(value.settingValue(5, at: 1).stops.map(\.value) == [1, 5])
        #expect(value.asConstant().isConstant && value.asConstant().stops[0].value == 1 && !value.isConstant)
    }
}

@Suite("Colours and classes")
struct ColourAndClassTests {
    @Test func aColourSurvivesThePickerAndTheStyleFile() throws {
        for hex: UInt32 in [0x000000, 0xFFFFFF, 0xAAD3EA, 0xC5DDB0, 0xFDD27F, 0x7FB5DC, 0x123456] {
            let color = MapColor(hex: hex)
            let back = ColorConversion.mapColor(ColorConversion.color(color))
            #expect(abs(back.red - color.red) < 1.0 / 255 && abs(back.green - color.green) < 1.0 / 255 && abs(back.blue - color.blue) < 1.0 / 255)
        }
        // A translucent colour keeps its opacity to a step of 1/255 (26/255 is the tint of military land).
        let tint = MapColor(hex: 0xD03030, alpha: 26.0 / 255)
        #expect(abs(ColorConversion.mapColor(ColorConversion.color(tint)).alpha - 26.0 / 255) < 1.0 / 255)
        #expect(ColorConversion.hex(MapColor(hex: 0xAAD3EA)) == "#AAD3EA" && ColorConversion.hex(tint) == "#D030301A")
    }

    @Test func everyClassIsInOneGroupAndHasAName() {
        let listed = ClassGroups.groups.flatMap(\.classes)
        #expect(Set(listed) == Set(FeatureClass.allCases) && listed.count == FeatureClass.allCases.count, "each class once")
        #expect(ClassGroups.name(of: .roadMajor) == "Road major" && ClassGroups.name(of: .waterEdge) == "Water edge" && ClassGroups.name(of: .sea) == "Sea")
        #expect(ClassGroups.name(of: .riverName) == "River name")
    }
}

@MainActor
@Suite("Style editor model")
struct StyleEditorModelTests {
    private func model(_ style: MapStyle = .standard) -> StyleEditorModel {
        StyleEditorModel(style: style, item: StyleItem(id: "Test.json", name: "Test", date: .now))
    }

    @Test func aChangeCanBeUndoneAndRedone() {
        let model = model()
        #expect(!model.isDirty && !model.canUndo)
        model.change { $0.name = "Mine" }
        #expect(model.style.name == "Mine" && model.isDirty && model.canUndo && !model.canRedo)
        model.undo()
        #expect(model.style.name == MapStyle.standard.name && !model.isDirty && model.canRedo)
        model.redo()
        #expect(model.style.name == "Mine")
        // A change after an undo ends the redo.
        model.undo()
        model.change { $0.name = "Other" }
        #expect(!model.canRedo)
    }

    @Test func aChangeThatChangesNothingIsNoStep() {
        let model = model()
        model.change { $0.name = MapStyle.standard.name }
        #expect(!model.canUndo && !model.isDirty)
    }

    @Test func theStepsOfOneSliderAreOneStepToUndo() {
        let model = model()
        for width in stride(from: 1.0, through: 5.0, by: 1.0) {
            model.change("class.roadMajor.width") { $0.classes[.roadMajor]?.layer = Int(width) + 40 }
        }
        #expect(model.style.classes[.roadMajor]?.layer == 45)
        model.undo()
        #expect(model.style.classes[.roadMajor] == MapStyle.standard.classes[.roadMajor], "back to before the first step")
        // Another field is another step.
        model.change("a") { $0.name = "A" }
        model.change("b") { $0.name = "B" }
        model.undo()
        #expect(model.style.name == "A")
    }

    @Test func revertGoesBackToTheSavedStyleAndCanBeUndone() {
        let model = model()
        model.change { $0.background = MapColor(hex: 0x112233) }
        model.revert()
        #expect(model.style == MapStyle.standard && !model.isDirty)
        model.undo()
        #expect(model.style.background == MapColor(hex: 0x112233) && model.isDirty)
    }

    @Test func aClassCanBeResetToTheBuiltInOrRemoved() {
        let model = model()
        model.change { $0.classes[.forest]?.fill = nil }
        model.resetClass(.forest, from: .standard)
        #expect(model.style.classes[.forest] == MapStyle.standard.classes[.forest])
        // A class that the other style does not have is removed.
        model.resetClass(.glacier, from: MapStyle(name: "Empty", background: .white, classes: [:]))
        #expect(model.style.classes[.glacier] == nil)
    }

    @Test func savingWritesTheFileAndTheStyleReadsBackTheSame() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geomapkit-edit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MapLibrary(root: root, defaults: UserDefaults(suiteName: "geomapkit-edit-\(UUID().uuidString)")!)
        let item = try library.addStyle(.standard, named: "Mine")
        let model = StyleEditorModel(style: try library.style(for: .user(item.id)), item: item)
        let revision = library.revision
        model.change { style in
            style.background = MapColor(hex: 0x102030)
            style.classes[.glacier]?.fill = FillStyle(color: ZoomValue(constant: MapColor(hex: 0xEEF6FF)))
            style.classes[.forest]?.visibleZoom = 8...24
        }
        #expect(model.isDirty)
        try model.save(into: library)
        #expect(!model.isDirty && library.revision > revision, "the map that uses the style is drawn again")
        let again = try library.style(for: .user(item.id))
        #expect(again == model.style)
        #expect(again.classes[.forest]?.visibleZoom == 8...24)
    }

    @Test func aStyleThatIsNotValidReadsAsASentence() {
        #expect(throws: MapStyleError.self) { try MapStyle(json: Data("{\"formatVersion\": 1}".utf8)) }
        do { _ = try MapStyle(json: Data("not json".utf8)) } catch { #expect("\(error)".contains("Invalid style")) }
    }
}
