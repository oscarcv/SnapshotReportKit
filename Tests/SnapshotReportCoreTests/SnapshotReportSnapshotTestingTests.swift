import Testing
@testable import SnapshotReportSnapshotTesting

@Test
func defaultAppearancePair() {
    #expect(SnapshotAppearanceConfiguration.defaultPair == [.light, .dark])
}

@Test
func allAppearanceModes() {
    #expect(SnapshotAppearanceConfiguration.all == [.light, .dark, .highContrastLight, .highContrastDark])
}
