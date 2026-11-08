/// What the placement of labels along lines remembers between candidates.
struct LineLabelState {
    /// Where each text has been placed along a line, so the same name does not repeat close by: the several ways of one
    /// street, or the two carriageways of a divided road, would otherwise each carry it.
    var centres: [String: [ScreenPoint]] = [:]
}
