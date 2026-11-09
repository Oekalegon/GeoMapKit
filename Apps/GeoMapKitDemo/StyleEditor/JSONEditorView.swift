import MapStyle
import SwiftUI

/// The whole style as JSON: everything the forms do not reach (bridges, tunnels, widths by lane) can be changed here. A change that is a
/// valid style shows in the preview at once; one that is not shows what is wrong and is not applied.
struct JSONEditorView: View {
    let model: StyleEditorModel
    @State private var text = ""
    @State private var error: String?
    /// The style that the text was made from or applied as, so that applying it does not make the text again.
    @State private var applied: MapStyle?
    /// The text as it was made from the style, to tell a change by the user from one by `load`.
    @State private var loadedText = ""

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .padding(.horizontal, 4)
            Divider()
            Group {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                } else {
                    Label("A valid style", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
            }
            .font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        .navigationTitle("JSON")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { load() }
        .onChange(of: model.reverts) { _, _ in load() }
        .onChange(of: text) { _, new in if new != loadedText { model.unappliedJSON = new } }
        // The forms or an undo changed the style: the text follows, unless the text itself made the change.
        .onChange(of: model.style) { _, new in if new != applied { load() } }
        // A pause after the last key press, then the text is read.
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            apply()
        }
    }

    private func load() {
        applied = model.style
        error = nil
        loadedText = (try? String(decoding: model.style.jsonData(), as: UTF8.self)) ?? ""
        model.unappliedJSON = nil
        text = loadedText
    }

    private func apply() {
        do {
            let style = try MapStyle(json: Data(text.utf8))
            error = nil
            model.unappliedJSON = nil
            guard style != model.style else { return }
            applied = style
            model.replace(with: style)
        } catch {
            self.error = "\(error)"
        }
    }
}
