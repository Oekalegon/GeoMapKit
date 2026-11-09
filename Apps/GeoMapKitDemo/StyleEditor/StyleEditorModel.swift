import FeatureStore
import Foundation
import MapStyle
import Observation

/// A style being edited: the working copy, what is saved, and the steps to undo.
///
/// The forms and the JSON editor both change the working copy through this model, so the preview and the undo see every change. The
/// file is only written by `save`.
@MainActor
@Observable
final class StyleEditorModel {
    /// The style as it is now, with every change.
    private(set) var style: MapStyle
    /// The style as it is in the file.
    private(set) var saved: MapStyle
    /// The file the style is saved to.
    let item: StyleItem

    private var undoStack: [MapStyle] = []
    private var redoStack: [MapStyle] = []
    /// The key of the last change, so that the many steps of a slider or a stepper are one step to undo.
    private var lastKey: String?
    private static let undoLimit = 100

    init(style: MapStyle, item: StyleItem) {
        self.style = style
        saved = style
        self.item = item
    }

    /// JSON text typed in the JSON editor that is not yet applied to the style (it is waiting for the pause, or it is not a valid style).
    var unappliedJSON: String?
    /// Counts the reverts, so that the JSON editor shows the text of the reverted style.
    private(set) var reverts = 0

    /// Whether there is anything that is not saved, including JSON that is not yet applied.
    var isDirty: Bool { style != saved || unappliedJSON != nil }
    /// Whether there is anything to go back from.
    var canRevert: Bool { isDirty }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Changes the working copy.
    ///
    /// - Parameters:
    ///   - key: Names what is being changed. Changes in a row with the same key are one step to undo.
    ///   - edit: The change.
    func change(_ key: String? = nil, _ edit: (inout MapStyle) -> Void) {
        var changed = style
        edit(&changed)
        guard changed != style else { return }
        if key == nil || key != lastKey {
            undoStack.append(style)
            if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        }
        lastKey = key
        redoStack.removeAll()
        style = changed
    }

    /// Replaces the working copy (the JSON editor read a valid style).
    func replace(with other: MapStyle, key: String? = "json") {
        change(key) { $0 = other }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(style)
        style = previous
        lastKey = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(style)
        style = next
        lastKey = nil
    }

    /// Goes back to the saved style (a step that can be undone).
    func revert() {
        unappliedJSON = nil
        reverts += 1
        change { $0 = saved }
    }

    /// Applies the JSON text that is still waiting (at Save and Close, so that a key press just before is not lost).
    ///
    /// - Throws: ``MapStyleError`` if the text is not a valid style; the style is left as it is.
    func applyUnappliedJSON() throws {
        guard let text = unappliedJSON else { return }
        let other = try MapStyle(json: Data(text.utf8))
        unappliedJSON = nil
        replace(with: other)
    }

    /// Switches a class on or off. Switching on restores what the saved style or `fallback` had for the class, and `fresh` if neither has it.
    func setDrawn(_ on: Bool, for featureClass: FeatureClass, fallback: MapStyle = .standard, fresh: ClassStyle) {
        change { style in
            style.classes[featureClass] = on ? (saved.classes[featureClass] ?? fallback.classes[featureClass] ?? fresh) : nil
        }
    }

    /// Takes the definition of one class from another style (the built-in one), or removes the class when that style has none.
    func resetClass(_ featureClass: FeatureClass, from base: MapStyle) {
        change { $0.classes[featureClass] = base.classes[featureClass] }
    }

    /// Writes the working copy to the file of the item.
    ///
    /// - Throws: ``LibraryError`` if the file cannot be written.
    func save(into library: MapLibrary) throws {
        try applyUnappliedJSON()
        try library.saveStyle(style, to: item)
        saved = style
    }
}
