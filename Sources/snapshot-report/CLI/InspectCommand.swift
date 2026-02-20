import Foundation

struct InspectCommand {
    static func run(arguments: [String]) throws {
        if arguments.contains("--help") || arguments.isEmpty {
            printUsage()
            return
        }

        let options = try parse(arguments: arguments)
        let result = try ProjectInspector().inspect(projectPath: options.projectPath)
        print(result.formattedReport(gitlab: options.gitlab))
    }

    private static func parse(arguments: [String]) throws -> Options {
        var projectPath: URL?
        var gitlab = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--project", "-p":
                index += 1
                guard index < arguments.count else { throw InspectError.missingValue("--project") }
                projectPath = URL(fileURLWithPath: arguments[index])
            case "--gitlab":
                gitlab = true
            default:
                throw InspectError.unknownArgument(arguments[index])
            }
            index += 1
        }
        guard let projectPath else { throw InspectError.missingValue("--project") }
        return Options(projectPath: projectPath, gitlab: gitlab)
    }

    private static func printUsage() {
        print("""
        snapshot-report inspect

        Usage:
          snapshot-report inspect --project MyApp.xcodeproj [options]

        Options:
          -p, --project <path>    Path to .xcodeproj
              --gitlab            Include a GitLab CI scheduled-pipeline snippet in output
              --help              Show help
        """)
    }

    private struct Options {
        let projectPath: URL
        let gitlab: Bool
    }
}

enum InspectError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)
    case pbxprojNotFound(URL)

    var description: String {
        switch self {
        case .missingValue(let flag): return "Missing value for \(flag)"
        case .unknownArgument(let arg): return "Unknown argument: \(arg)"
        case .pbxprojNotFound(let path): return "project.pbxproj not found at \(path.path)"
        }
    }
}

// MARK: - Inspector

struct ProjectInspector {
    func inspect(projectPath: URL) throws -> ProjectInspectionResult {
        let pbxprojPath = projectPath.appendingPathComponent("project.pbxproj")
        guard FileManager.default.fileExists(atPath: pbxprojPath.path) else {
            throw InspectError.pbxprojNotFound(projectPath)
        }

        let pbxprojContent = try String(contentsOf: pbxprojPath, encoding: .utf8)
        let snapshotTargets = detectSnapshotTargets(pbxproj: pbxprojContent)
        let schemes = listSchemes(projectPath: projectPath)

        return ProjectInspectionResult(
            snapshotTargets: snapshotTargets,
            allSchemes: schemes,
            projectPath: projectPath
        )
    }

    /// Scans the pbxproj text for references to swift-snapshot-testing within
    /// PBXNativeTarget sections and returns the matching target names.
    func detectSnapshotTargets(pbxproj: String) -> [String] {
        let markers = [
            "swift-snapshot-testing",
            "SnapshotReportTesting",
            "SnapshotReportSnapshotTesting",
            "SnapshotTesting"
        ]
        let lines = pbxproj.components(separatedBy: "\n")

        var targetNames: [String] = []
        var inTargetSection = false
        var currentTargetName: String?
        var currentTargetHasSnapshot = false

        for line in lines {
            if line.contains("/* Begin PBXNativeTarget section */") {
                inTargetSection = true
                continue
            }
            if line.contains("/* End PBXNativeTarget section */") {
                if currentTargetHasSnapshot, let name = currentTargetName {
                    targetNames.append(name)
                }
                inTargetSection = false
                currentTargetName = nil
                currentTargetHasSnapshot = false
                continue
            }

            guard inTargetSection else { continue }

            // Detect the start of a new target block: <ID> /* <TargetName> */ = {
            if line.contains("= {"), let name = extractComment(from: line) {
                if currentTargetHasSnapshot, let prev = currentTargetName {
                    targetNames.append(prev)
                }
                currentTargetName = name
                currentTargetHasSnapshot = false
            }

            if markers.contains(where: { line.contains($0) }) {
                currentTargetHasSnapshot = true
            }
        }

        return targetNames.sorted()
    }

    private func extractComment(from line: String) -> String? {
        guard
            let start = line.range(of: "/* "),
            let end = line.range(of: " */", range: start.upperBound..<line.endIndex)
        else { return nil }
        return String(line[start.upperBound..<end.lowerBound])
    }

    private func listSchemes(projectPath: URL) -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["-list", "-json", "-project", projectPath.path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let project = json["project"] as? [String: Any],
            let schemes = project["schemes"] as? [String]
        else { return [] }
        return schemes
    }
}

// MARK: - Result

struct ProjectInspectionResult {
    let snapshotTargets: [String]
    let allSchemes: [String]
    let projectPath: URL

    func formattedReport(gitlab: Bool) -> String {
        var lines: [String] = []
        lines.append("=== SnapshotReportKit Inspection: \(projectPath.lastPathComponent) ===\n")

        if snapshotTargets.isEmpty {
            lines.append("No test targets referencing swift-snapshot-testing or SnapshotReportTesting were detected.")
            lines.append("If your project uses snapshot testing, ensure the package dependency name matches one of:")
            lines.append("  • swift-snapshot-testing")
            lines.append("  • SnapshotReportTesting (preferred)")
            lines.append("  • SnapshotReportSnapshotTesting (legacy)")
            lines.append("  • SnapshotTesting")
        } else {
            lines.append("Snapshot testing targets detected:")
            snapshotTargets.forEach { lines.append("  • \($0)") }
            lines.append("")
            lines.append("Recommended environment variables to set in each scheme's test action:")
            lines.append("  SNAPSHOT_REPORT_OUTPUT_DIR = $(SRCROOT)/.artifacts/snapshot-runs")
            lines.append("  SRCROOT                    = $(SRCROOT)")
            lines.append("  SCHEME_NAME                = <your scheme name>")
            lines.append("  GIT_BRANCH                 = $(GIT_BRANCH)  # or $CI_COMMIT_REF_NAME on GitLab")
            lines.append("  TEST_PLAN_NAME             = <your test plan name>")
            lines.append("")
            lines.append("Add this call at the start of each snapshot test suite's setUp():")
            lines.append("  configureSnapshotReport(reportName: \"<TargetName> Snapshots\")")
        }

        if !allSchemes.isEmpty {
            lines.append("")
            lines.append("Schemes found: \(allSchemes.joined(separator: ", "))")
        }

        if gitlab {
            lines.append("")
            lines.append(gitlabCISnippet())
        }

        return lines.joined(separator: "\n")
    }

    private func gitlabCISnippet() -> String {
        let scheme = allSchemes.first ?? "<your-scheme>"
        let targets = snapshotTargets.isEmpty ? ["<your-snapshot-test-target>"] : snapshotTargets
        let testTargetComment = targets.map { "# \($0)" }.joined(separator: "\n        ")

        return """
        # === Suggested .gitlab-ci.yml snippet for scheduled snapshot runs ===

        snapshot-tests:
          stage: test
          script:
            - xcodebuild test
                -project \(projectPath.lastPathComponent)
                -scheme \(scheme)
                -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'
                SNAPSHOT_REPORT_OUTPUT_DIR=$CI_PROJECT_DIR/.artifacts/snapshot-runs
                SRCROOT=$CI_PROJECT_DIR
                GIT_BRANCH=$CI_COMMIT_REF_NAME
                SCHEME_NAME=\(scheme)
            # Targets with snapshot tests:
            \(testTargetComment)
            - snapshot-report
                --input-dir .artifacts/snapshot-runs
                --output .artifacts/snapshot-report
                --format json,junit,html
          artifacts:
            paths:
              - .artifacts/snapshot-runs/
              - .artifacts/snapshot-report/
            reports:
              junit: .artifacts/snapshot-report/report.junit.xml
          only:
            - schedules
        """
    }
}
