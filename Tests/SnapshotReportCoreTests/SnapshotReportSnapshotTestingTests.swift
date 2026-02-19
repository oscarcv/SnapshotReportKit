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

@Test
func defaultSupportedOSMajorVersions() {
    #expect(SnapshotDevicePreset.defaultSupportedOSMajorVersions == [15, 16, 17, 18, 26])
}

@Test
func deviceCompatibilityValidationUsesConfiguredVersions() {
    let configuration = SnapshotDeviceConfiguration(
        preset: .iPhone11Pro,
        supportedOSMajorVersions: [15, 16, 17, 18, 26]
    )

    #expect((try? configuration.validateCompatibility(osMajorVersion: 26)) != nil)
    #expect((try? configuration.validateCompatibility(osMajorVersion: 14)) == nil)
}
