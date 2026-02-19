import Foundation
import SnapshotReportCore

struct CLI {
    static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--help") || arguments.isEmpty {
            printUsage()
            return
        }

        let options = try parse(arguments: arguments)
        try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)

        let reports = try options.inputs.map(SnapshotReportIO.loadReport)
        let mergedReport = SnapshotReportAggregator.merge(reports: reports, name: options.reportName)

        for format in options.formats {
            try SnapshotReportWriters.write(mergedReport, format: format, options: .init(outputDirectory: options.outputDirectory, htmlTemplatePath: options.htmlTemplate))
        }

        print("Generated report \(options.formats.map(\.rawValue).joined(separator: ", ")) at \(options.outputDirectory.path)")
    }

    private static func parse(arguments: [String]) throws -> Options {
        var inputs: [URL] = []
        var formats: [OutputFormat] = [.json, .junit, .html]
        var outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("snapshot-report-output", isDirectory: true)
        var htmlTemplate: String?
        var reportName: String?

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
            case "--html-template":
                index += 1
                guard index < arguments.count else { throw SnapshotReportError.invalidInput("Missing value for --html-template") }
                htmlTemplate = arguments[index]
            case "--name":
                index += 1
                guard index < arguments.count else { throw SnapshotReportError.invalidInput("Missing value for --name") }
                reportName = arguments[index]
            default:
                throw SnapshotReportError.invalidInput("Unknown argument: \(argument)")
            }

            index += 1
        }

        guard !inputs.isEmpty else {
            throw SnapshotReportError.invalidInput("At least one --input is required")
        }

        return Options(inputs: inputs, formats: formats, outputDirectory: outputDirectory, htmlTemplate: htmlTemplate, reportName: reportName)
    }

    private static func printUsage() {
        print(
            """
            snapshot-report

            Usage:
              snapshot-report --input report1.json --input report2.json [options]

            Options:
              -i, --input <path>          Input report JSON (repeatable)
              -f, --format <list>         Comma list: json,junit,html (default: json,junit,html)
              -o, --output <dir>          Output directory (default: ./snapshot-report-output)
                  --html-template <path>  Custom stencil template for html report
                  --name <string>         Override merged report name
                  --help                  Show help
            """
        )
    }

    private struct Options {
        let inputs: [URL]
        let formats: [OutputFormat]
        let outputDirectory: URL
        let htmlTemplate: String?
        let reportName: String?
    }
}

do {
    try CLI.run()
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
