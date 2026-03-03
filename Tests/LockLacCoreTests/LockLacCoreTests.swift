import Testing
@testable import LockLacCore

@Test func versionExists() {
    #expect(!LockLacCore.version.isEmpty)
}
