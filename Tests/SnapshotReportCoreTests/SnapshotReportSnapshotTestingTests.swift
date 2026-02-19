import Testing
@testable import SnapshotReportSnapshotTesting

@Test
func defaultAppearancePair() {
    #expect(SnapshotAppearanceConfiguration.defaultPair == [.light, .dark])
}

@Test
func allAppearanceModes() {
    #expect(SnapshotAppearanceConfiguration.all == [.light, .dark, .highContrastLight, .highContrastDark])
    #expect(SnapshotAppearanceConfiguration.reportOrder == [.highContrastLight, .light, .dark, .highContrastDark])
}

@Test
func defaultAllowedOSMajorVersions() {
    #expect(SnapshotDevicePreset.allowedOSMajorVersions == [15, 16, 17, 18, 26])
    #expect(SnapshotDevicePreset.defaultConfiguredOSMajorVersion == 26)
}

@Test
func deviceCompatibilityValidationUsesConfiguredVersions() {
    let configuration = SnapshotDeviceConfiguration(
        preset: .iPhone11Pro,
        configuredOSMajorVersion: 26
    )

    #expect((try? configuration.validateCompatibility(osMajorVersion: 26)) != nil)
    #expect((try? configuration.validateCompatibility(osMajorVersion: 18)) == nil)
}
