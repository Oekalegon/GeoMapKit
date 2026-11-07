/// Counts of the problems met while assembling one multipolygon, for the build report.
struct AssemblyReport: Equatable {
    /// Chains of ways that did not close into a ring.
    var unclosedChains = 0
    /// Rings dropped because they had fewer than four points or no area.
    var degenerateRings = 0
    /// Inner rings that no outer ring contains. They are ignored; the polygons stay valid.
    var orphanInnerRings = 0
    /// Member ways that are missing from the extract or have missing nodes.
    var missingMembers = 0
    /// Members listed twice with the same way and role.
    var duplicateMembers = 0
}
