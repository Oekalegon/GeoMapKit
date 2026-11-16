import FeatureStoreBuilder
import OSMPBF

/// A step of the work on one block, and how much of the block's time it takes: the weights of the progress of a block.
///
/// The weights are the seconds of each step in a release build of a block of Franche-Comté (47.0 to 48.3 N, 5.6 to 7.1 E; one source
/// file; 33 s for the block): the nodes of the cut 1.7, the ways 2.6, the relations 0.7, the member ways 2.5, the outside nodes 1.4, the
/// assembly 0.6; then the build: the sea 0.1, the relations 1.9, the ways 15.6, the nodes 1.2, the writing 0.7; and 3.0 for what is left (the
/// check and the file). A block that is cut from several files spends more of its time in the cut, so the bar is not exact there; it
/// only has to move steadily and never go back.
enum BlockStep: Int, CaseIterable {
    case cutNodes, cutWays, cutRelations, cutMemberWays, cutOutsideNodes, cutAssembly
    case buildSea, buildRelations, buildWays, buildNodes, buildWriting
    case finishing

    /// The seconds that the step takes in the measured block.
    var weight: Double {
        switch self {
        case .cutNodes: 1.7
        case .cutWays: 2.6
        case .cutRelations: 0.7
        case .cutMemberWays: 2.5
        case .cutOutsideNodes: 1.4
        case .cutAssembly: 0.6
        case .buildSea: 0.1
        case .buildRelations: 1.9
        case .buildWays: 15.6
        case .buildNodes: 1.2
        case .buildWriting: 0.7
        case .finishing: 3.0
        }
    }

    init(_ pass: AreaCutter.Pass) {
        switch pass {
        case .insideNodes: self = .cutNodes
        case .ways: self = .cutWays
        case .relations: self = .cutRelations
        case .memberWays: self = .cutMemberWays
        case .outsideNodes: self = .cutOutsideNodes
        case .assembly: self = .cutAssembly
        }
    }

    init(_ stage: BuildStage) {
        switch stage {
        case .sea: self = .buildSea
        case .relations: self = .buildRelations
        case .ways: self = .buildWays
        case .nodes: self = .buildNodes
        case .writing: self = .buildWriting
        }
    }

    private static let total = allCases.reduce(0) { $0 + $1.weight }

    /// How much of the block is done when the step has begun, from 0 to 1.
    var start: Double { Self.allCases.prefix { $0 != self }.reduce(0) { $0 + $1.weight } / Self.total }

    /// How much of the block is done when `part` (0 to 1) of the step is done.
    func fraction(part: Double) -> Double { start + weight / Self.total * min(max(part, 0), 1) }
}
