import Foundation
import SnapshotReportCore
import SnapshotReportOdiff
import SnapshotReportCLI

struct CLI {
    static func run() throws {
        CLIUI.header("snapshot-report")
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

        CLIUI.step("Resolving input files")
        let resolvedInputs = try resolveInputs(options: options)

        CLIUI.step("Loading JSON reports (\(resolvedInputs.count))")
        let reports = try _loadJSONReports(inputs: resolvedInputs, jobs: options.jobs) { completed, total, input in
            CLIUI.progress("JSON \(completed)/\(total): \(input.lastPathComponent)")
        }

        CLIUI.step("Extracting xcresult bundles (\(options.xcresultInputs.count))")
        let xcresultReports = try _readXCResultReports(inputs: options.xcresultInputs, jobs: options.jobs) { completed, total, input in
            CLIUI.progress("XCResult \(completed)/\(total): \(input.lastPathComponent)")
        }

        CLIUI.step("Merging report data")
        let mergedReport = SnapshotReportAggregator.merge(reports: reports + xcresultReports, name: options.reportName)

        let effectiveOdiffPath = options.odiffPath ?? _resolveOnPATH("odiff")
        let finalReport: SnapshotReport
        if let odiffPath = effectiveOdiffPath {
            CLIUI.step("Generating odiff attachments")
            finalReport = OdiffProcessor(odiffBinaryPath: odiffPath).process(report: mergedReport)
        } else {
            finalReport = mergedReport
        }

        CLIUI.step("Generating output formats (\(options.formats.count))")
        try _writeReports(
            finalReport,
            formats: options.formats,
            outputDirectory: options.outputDirectory,
            htmlTemplate: options.htmlTemplate,
            jobs: options.jobs
        ) { completed, total, format in
            CLIUI.progress("Output \(completed)/\(total): \(format.rawValue)")
        }

        CLIUI.success("Generated report \(options.formats.map(\.rawValue).joined(separator: ", ")) at \(options.outputDirectory.path)")
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
        var jobs = max(1, ProcessInfo.processInfo.activeProcessorCount)

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
            case "--jobs":
                index += 1
                guard index < arguments.count else { throw SnapshotReportError.invalidInput("Missing value for --jobs") }
                guard let parsed = Int(arguments[index]), parsed > 0 else {
                    throw SnapshotReportError.invalidInput("--jobs must be a positive integer")
                }
                jobs = parsed
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
            odiffPath: odiffPath,
            jobs: jobs
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
                  --jobs <n>              Max parallel xcresult reads (default: CPU count)
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
        let jobs: Int
    }
}

private func _readXCResultReports(
    inputs: [URL],
    jobs: Int,
    progress: @escaping @Sendable (_ completed: Int, _ total: Int, _ input: URL) -> Void = { _, _, _ in }
) throws -> [SnapshotReport] {
    guard !inputs.isEmpty else { return [] }
    if inputs.count == 1 {
        let report = try XCResultReader().read(xcresultPath: inputs[0])
        progress(1, 1, inputs[0])
        return [report]
    }

    let workerCount = max(1, min(jobs, inputs.count))
    let queue = DispatchQueue(label: "snapshot-report.xcresult.queue", attributes: .concurrent)
    let semaphore = DispatchSemaphore(value: workerCount)
    let state = XCResultReadState()
    let group = DispatchGroup()

    for (index, input) in inputs.enumerated() {
        group.enter()
        semaphore.wait()
        queue.async {
            defer {
                semaphore.signal()
                group.leave()
            }

            do {
                let report = try XCResultReader().read(xcresultPath: input)
                state.setReport(report, at: index)
                let completed = state.incrementCompleted()
                progress(completed, inputs.count, input)
            } catch {
                state.setFirstErrorIfNeeded(error)
            }
        }
    }

    group.wait()
    if let firstError = state.firstError() { throw firstError }

    return inputs.indices.compactMap { state.report(at: $0) }
}

private final class XCResultReadState: @unchecked Sendable {
    private let lock = NSLock()
    private var reportsByIndex: [Int: SnapshotReport] = [:]
    private var storedError: Error?
    private var completedCount = 0

    func setReport(_ report: SnapshotReport, at index: Int) {
        lock.lock()
        reportsByIndex[index] = report
        lock.unlock()
    }

    func report(at index: Int) -> SnapshotReport? {
        lock.lock()
        defer { lock.unlock() }
        return reportsByIndex[index]
    }

    func setFirstErrorIfNeeded(_ error: Error) {
        lock.lock()
        if storedError == nil {
            storedError = error
        }
        lock.unlock()
    }

    func incrementCompleted() -> Int {
        lock.lock()
        completedCount += 1
        let value = completedCount
        lock.unlock()
        return value
    }

    func firstError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }
}

private func _loadJSONReports(
    inputs: [URL],
    jobs: Int,
    progress: @escaping @Sendable (_ completed: Int, _ total: Int, _ input: URL) -> Void = { _, _, _ in }
) throws -> [SnapshotReport] {
    guard !inputs.isEmpty else { return [] }
    if inputs.count == 1 {
        let report = try SnapshotReportIO.loadReport(from: inputs[0])
        progress(1, 1, inputs[0])
        return [report]
    }

    let workerCount = max(1, min(jobs, inputs.count))
    let queue = DispatchQueue(label: "snapshot-report.json.queue", attributes: .concurrent)
    let semaphore = DispatchSemaphore(value: workerCount)
    let state = XCResultReadState()
    let group = DispatchGroup()

    for (index, input) in inputs.enumerated() {
        group.enter()
        semaphore.wait()
        queue.async {
            defer {
                semaphore.signal()
                group.leave()
            }

            do {
                let report = try SnapshotReportIO.loadReport(from: input)
                state.setReport(report, at: index)
                let completed = state.incrementCompleted()
                progress(completed, inputs.count, input)
            } catch {
                state.setFirstErrorIfNeeded(error)
            }
        }
    }

    group.wait()
    if let firstError = state.firstError() { throw firstError }
    return inputs.indices.compactMap { state.report(at: $0) }
}

private func _writeReports(
    _ report: SnapshotReport,
    formats: [OutputFormat],
    outputDirectory: URL,
    htmlTemplate: String?,
    jobs: Int,
    progress: @escaping @Sendable (_ completed: Int, _ total: Int, _ format: OutputFormat) -> Void = { _, _, _ in }
) throws {
    if formats.count == 1 {
        let format = formats[0]
        try SnapshotReportWriters.write(
            report,
            format: format,
            options: .init(outputDirectory: outputDirectory, htmlTemplatePath: htmlTemplate)
        )
        progress(1, 1, format)
        return
    }

    let workerCount = max(1, min(jobs, formats.count))
    let queue = DispatchQueue(label: "snapshot-report.write.queue", attributes: .concurrent)
    let semaphore = DispatchSemaphore(value: workerCount)
    let state = ReportWriteState()
    let group = DispatchGroup()

    for format in formats {
        group.enter()
        semaphore.wait()
        queue.async {
            defer {
                semaphore.signal()
                group.leave()
            }
            do {
                try SnapshotReportWriters.write(
                    report,
                    format: format,
                    options: .init(outputDirectory: outputDirectory, htmlTemplatePath: htmlTemplate)
                )
                let completed = state.incrementCompleted()
                progress(completed, formats.count, format)
            } catch {
                state.setFirstErrorIfNeeded(error)
            }
        }
    }

    group.wait()
    if let firstError = state.firstError() {
        throw firstError
    }
}

private final class ReportWriteState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?
    private var completedCount = 0

    func incrementCompleted() -> Int {
        lock.lock()
        completedCount += 1
        let value = completedCount
        lock.unlock()
        return value
    }

    func setFirstErrorIfNeeded(_ error: Error) {
        lock.lock()
        if storedError == nil {
            storedError = error
        }
        lock.unlock()
    }

    func firstError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }
}

private enum CLIUI {
    private static let lock = NSLock()
    private static let prefix = "[snapshot-report]"

    static func header(_ title: String) {
        log("\(prefix) \(title)")
    }

    static func step(_ message: String) {
        log("\(prefix) step: \(message)")
    }

    static func progress(_ message: String) {
        log("\(prefix) progress: \(message)")
    }

    static func success(_ message: String) {
        log("\(prefix) success: \(message)")
    }

    static func log(_ message: String) {
        lock.lock()
        print(message)
        lock.unlock()
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
