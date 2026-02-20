import Foundation
import SnapshotReportCore
import SnapshotReportOdiff
import SnapshotReportCLI

struct CLI {
    static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.first == "inspect" {
            try InspectCommand.run(arguments: Array(arguments.dropFirst()))
            return
        }

        if arguments.contains("--help") || arguments.isEmpty {
            printUsage()
            return
        }

        let options = try parse(arguments: arguments)
        try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)

        let resolvedInputs = try resolveInputs(options: options)
        let reports = try resolvedInputs.map(SnapshotReportIO.loadReport)
        let xcresultReports = try options.xcresultInputs.map { try XCResultReader().read(xcresultPath: $0) }
        let mergedReport = SnapshotReportAggregator.merge(reports: reports + xcresultReports, name: options.reportName)

        let effectiveOdiffPath = options.odiffPath ?? _resolveOnPATH("odiff")
        let finalReport: SnapshotReport
        if let odiffPath = effectiveOdiffPath {
            finalReport = OdiffProcessor(odiffBinaryPath: odiffPath).process(report: mergedReport)
        } else {
            finalReport = mergedReport
        }

        for format in options.formats {
            try SnapshotReportWriters.write(finalReport, format: format, options: .init(outputDirectory: options.outputDirectory, htmlTemplatePath: options.htmlTemplate))
        }

        print("Generated report \(options.formats.map(\.rawValue).joined(separator: ", ")) at \(options.outputDirectory.path)")
    }

    private static func parse(arguments: [String]) throws -> Options {
        var inputs: [URL] = []
        var inputDirectories: [URL] = []
        var xcresultInputs: [URL] = []
        var formats: [OutputFormat] = [.json, .junit, .html]
        var outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("snapshot-report-output", isDirectory: true)
        var htmlTemplate: String?
        var reportName: String?
        var odiffPath: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--input", "-i":
                index += 1
                guard index < arguments.count else { throw SnapshotReportError.invalidInput("Missing value for --input") }
                inputs.append(URL(fileURLWithPath: arguments[index]))
            case "--format", "-f":
                index += 1
                guard index < arguments.count else { throw SnapshotReportError.invalidInput("Missing value for --format") }
                formats = try arguments[index]
                    .split(separator: ",")
                    .map { value in
                        guard let format = OutputFormat(rawValue: String(value).trimmingCharacters(in: .whitespacesAndNewlines)) else {
                            throw SnapshotReportError.invalidInput("Unknown format: \(value)")
                        }
                        return format
                    }
            case "--output", "-o":
                index += 1
                guard index < arguments.count else { throw SnapshotReportError.invalidInput("Missing value for --output") }
                outputDirectory = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--input-dir":
                index += 1
                guard index < arguments.count else { throw SnapshotReportError.invalidInput("Missing value for --input-dir") }
                inputDirectories.append(URL(fileURLWithPath: arguments[index], isDirectory: true))
            case "--html-template":
                index += 1
                guard index < arguments.count else { throw SnapshotReportError.invalidInput("Missing value for --html-template") }
                htmlTemplate = arguments[index]
            case "--name":
                index += 1
                guard index < arguments.count else { throw SnapshotReportError.invalidInput("Missing value for --name") }
                reportName = arguments[index]
            case "--xcresult":
                index += 1
                guard index < arguments.count else { throw SnapshotReportError.invalidInput("Missing value for --xcresult") }
                xcresultInputs.append(URL(fileURLWithPath: arguments[index]))
            case "--odiff":
                index += 1
                guard index < arguments.count else { throw SnapshotReportError.invalidInput("Missing value for --odiff") }
                odiffPath = arguments[index]
            default:
                throw SnapshotReportError.invalidInput("Unknown argument: \(argument)")
            }

            index += 1
        }

        guard !inputs.isEmpty || !inputDirectories.isEmpty || !xcresultInputs.isEmpty else {
            throw SnapshotReportError.invalidInput("At least one --input, --input-dir, or --xcresult is required")
        }

        return Options(
            inputs: inputs,
            inputDirectories: inputDirectories,
            xcresultInputs: xcresultInputs,
            formats: formats,
            outputDirectory: outputDirectory,
            htmlTemplate: htmlTemplate,
            reportName: reportName,
            odiffPath: odiffPath
        )
    }

    private static func resolveInputs(options: Options) throws -> [URL] {
        var resolved = options.inputs
        let fileManager = FileManager.default

        for directory in options.inputDirectories {
            guard fileManager.fileExists(atPath: directory.path) else { continue }

            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: nil
            )

            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension.lowercased() == "json" {
                    resolved.append(url)
                }
            }
        }

        guard !resolved.isEmpty || !options.xcresultInputs.isEmpty else {
            throw SnapshotReportError.invalidInput("No JSON inputs found from --input/--input-dir")
        }

        return resolved
    }

    private static func printUsage() {
        print(
            """
            snapshot-report

            Usage:
              snapshot-report --input report1.json --input report2.json [options]
              snapshot-report inspect --project MyApp.xcodeproj [--gitlab]

            Options:
              -i, --input <path>          Input report JSON (repeatable)
                  --input-dir <dir>       Recursively include all JSON reports from a directory
                  --xcresult <path>       Input xcresult bundle (repeatable, macOS only)
              -f, --format <list>         Comma list: json,junit,html (default: json,junit,html)
              -o, --output <dir>          Output directory (default: ./snapshot-report-output)
                  --html-template <path>  Custom stencil template for html report
                  --name <string>         Override merged report name
                  --odiff <path>          Path to odiff binary (default: auto-detect on PATH)
                  --help                  Show help
            """
        )
    }

    private struct Options {
        let inputs: [URL]
        let inputDirectories: [URL]
        let xcresultInputs: [URL]
        let formats: [OutputFormat]
        let outputDirectory: URL
        let htmlTemplate: String?
        let reportName: String?
        let odiffPath: String?
    }
}

private func _resolveOnPATH(_ name: String) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [name]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return output.flatMap { $0.isEmpty ? nil : $0 }
}

do {
    try CLI.run()
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
