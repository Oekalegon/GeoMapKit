import Testing

@testable import MapBuilder

/// How many blocks are built at once when the user does not say.
@Suite("Recommended jobs")
struct RecommendedJobsTests {
    // `physicalMemory` is in binary units: a Mac sold as 16 GB reports 16 GiB.
    private let gib: UInt64 = 1 << 30

    @Test("Big Macs get four jobs, however much memory they have above 20 GiB")
    func bigMacs() {
        #expect(BlockRequest.recommendedJobs(cores: 12, memory: 64 * gib) == 4)
        #expect(BlockRequest.recommendedJobs(cores: 18, memory: 48 * gib) == 4, "the Mac of the measurement")
        #expect(BlockRequest.recommendedJobs(cores: 10, memory: 32 * gib) == 4)
        #expect(BlockRequest.recommendedJobs(cores: 10, memory: 24 * gib) == 4)
    }

    @Test("One job more for every 3 GiB above the 8 GiB that are left free")
    func steps() {
        #expect(BlockRequest.recommendedJobs(cores: 16, memory: 20 * gib) == 4)
        #expect(BlockRequest.recommendedJobs(cores: 16, memory: 19 * gib) == 3)
        #expect(BlockRequest.recommendedJobs(cores: 16, memory: 17 * gib) == 3)
        #expect(BlockRequest.recommendedJobs(cores: 16, memory: 16 * gib) == 2, "a Mac sold as 16 GB")
        #expect(BlockRequest.recommendedJobs(cores: 16, memory: 14 * gib) == 2)
        #expect(BlockRequest.recommendedJobs(cores: 16, memory: 11 * gib) == 1)
        #expect(BlockRequest.recommendedJobs(cores: 16, memory: 8 * gib) == 1, "a Mac sold as 8 GB leaves nothing for more than one block")
    }

    @Test("Few cores or less memory than the margin still give one job, and never more than half the cores")
    func floors() {
        #expect(BlockRequest.recommendedJobs(cores: 2, memory: 64 * gib) == 1)
        #expect(BlockRequest.recommendedJobs(cores: 1, memory: 1 * gib) == 1, "less memory than the margin")
        #expect(BlockRequest.recommendedJobs(cores: 4, memory: 64 * gib) == 2)
        #expect(BlockRequest.recommendedJobs(cores: 6, memory: 64 * gib) == 3)
    }

    @Test("The default reads this machine and is at least one")
    func thisMachine() {
        let jobs = BlockRequest.recommendedJobs()
        #expect((1...4).contains(jobs))
    }
}
