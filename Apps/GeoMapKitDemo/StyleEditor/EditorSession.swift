import Foundation

/// A style being edited, for `sheet(item:)`.
struct EditorSession: Identifiable {
    let model: StyleEditorModel
    let preview: PreviewMap?
    var id: String { model.item.id }
}
