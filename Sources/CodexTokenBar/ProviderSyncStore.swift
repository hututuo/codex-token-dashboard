import AppKit
import Foundation
import SQLite3

struct ProviderSyncProviderCount: Identifiable, Equatable {
    let id = UUID()
    let provider: String
    let count: Int
}

struct ProviderSyncSQLiteCount: Identifiable, Equatable {
    let id = UUID()
    let provider: String
    let archived: Int
    let count: Int
}

struct ProviderSyncSnapshot: Equatable {
    var codexHome: String = "~/.codex"
    var detectedProvider: String = "openai"
    var providerSource: String = "等待扫描"
    var sessionFilesFound: Int = 0
    var sessionProviders: [ProviderSyncProviderCount] = []
    var sqliteProviders: [ProviderSyncSQLiteCount] = []
    var invalidSessionFiles: Int = 0
    var changedSessionFiles: Int = 0
    var sqliteRowsChanged: Int = 0
    var sqliteIntegrity: String = "未验证"
    var sessionIndexCurrentThreadPresent: Bool = false
    var sessionIndexRows: Int = 0
    var codexRunning: Bool = false
    var lastBackupPath: String?
    var status: String = "扫描后可同步历史 provider"
    var isWorking: Bool = false

    var hasMixedProviders: Bool {
        sessionProviders.count > 1 || sqliteProviders.map(\.provider).uniqued().count > 1
    }

    var compactProviderSummary: String {
        guard !sessionProviders.isEmpty else { return "未扫描" }
        return sessionProviders
            .prefix(3)
            .map { "\($0.provider) \($0.count)" }
            .joined(separator: "  ")
    }
}

@MainActor
final class ProviderSyncStore: ObservableObject {
    @Published private(set) var snapshot = ProviderSyncSnapshot()
    @Published var includeArchivedSessions = true
    @Published var dryRunOnly = false
    @Published var manualProvider = ""

    private var task: Task<Void, Never>?

    func scan(dataSource: CodexDataSource?) {
        run(dataSource: dataSource) { engine, source in
            try engine.scan(codexHome: source.codexHome, includeArchivedSessions: self.includeArchivedSessions)
        }
    }

    func sync(dataSource: CodexDataSource?) {
        run(dataSource: dataSource) { engine, source in
            let targetProvider = self.effectiveTargetProvider()
            return try engine.sync(
                codexHome: source.codexHome,
                includeArchivedSessions: self.includeArchivedSessions,
                targetProviderOverride: targetProvider,
                dryRunOnly: self.dryRunOnly
            )
        }
    }

    func backup(dataSource: CodexDataSource?) {
        run(dataSource: dataSource) { engine, source in
            let targetProvider = self.effectiveTargetProvider()
            return try engine.sync(
                codexHome: source.codexHome,
                includeArchivedSessions: self.includeArchivedSessions,
                targetProviderOverride: targetProvider,
                dryRunOnly: true
            )
        }
    }

    func verify(dataSource: CodexDataSource?) {
        run(dataSource: dataSource) { engine, source in
            let targetProvider = self.effectiveTargetProvider()
            return try engine.verify(
                codexHome: source.codexHome,
                includeArchivedSessions: self.includeArchivedSessions,
                targetProviderOverride: targetProvider
            )
        }
    }

    func rollbackLatest(dataSource: CodexDataSource?) {
        run(dataSource: dataSource) { engine, source in
            try engine.rollbackLatest(codexHome: source.codexHome)
        }
    }

    private func effectiveTargetProvider() -> String? {
        let trimmed = manualProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func run(
        dataSource: CodexDataSource?,
        operation: @escaping (ProviderSyncEngine, CodexDataSource) throws -> ProviderSyncSnapshot
    ) {
        task?.cancel()
        guard let dataSource else {
            snapshot.status = "没有可用的 Codex Home"
            return
        }

        var working = snapshot
        working.codexHome = dataSource.displayPath
        working.isWorking = true
        working.status = "处理中..."
        snapshot = working

        task = Task {
            let result = await Task.detached(priority: .utility) {
                do {
                    return Result<ProviderSyncSnapshot, Error>.success(try operation(ProviderSyncEngine(), dataSource))
                } catch {
                    return Result<ProviderSyncSnapshot, Error>.failure(error)
                }
            }.value

            await MainActor.run {
                switch result {
                case .success(let next):
                    snapshot = next
                case .failure(let error):
                    var failed = snapshot
                    failed.isWorking = false
                    failed.status = error.localizedDescription
                    snapshot = failed
                }
            }
        }
    }
}

private struct ProviderSyncReport {
    var codexHome: URL
    var targetProvider: String
    var providerSource: String
    var sessionFiles: [URL]
    var sessionProviders: [String: Int]
    var invalidSessionFiles: Int
    var sqliteProviders: [ProviderSyncSQLiteProvider]
    var sqliteIntegrity: String
    var latestThreadID: String?
    var sessionIndexIDs: Set<String>
    var sessionIndexRows: Int
    var codexRunning: Bool
}

private struct ProviderSyncSQLiteProvider {
    var provider: String
    var archived: Int
    var count: Int
}

private struct ProviderSyncThreadIndexRow {
    var id: String
    var title: String
    var updatedAt: Date
}

private final class ProviderSyncEngine {
    private let fileManager = FileManager.default
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    func scan(codexHome: URL, includeArchivedSessions: Bool) throws -> ProviderSyncSnapshot {
        let report = try makeReport(codexHome: codexHome, includeArchivedSessions: includeArchivedSessions, targetProviderOverride: nil)
        return snapshot(from: report, status: "扫描完成")
    }

    func verify(codexHome: URL, includeArchivedSessions: Bool, targetProviderOverride: String?) throws -> ProviderSyncSnapshot {
        let report = try makeReport(codexHome: codexHome, includeArchivedSessions: includeArchivedSessions, targetProviderOverride: targetProviderOverride)
        let allSessionsMatch = report.sessionProviders.keys.allSatisfy { $0 == report.targetProvider }
        let allSQLiteMatch = report.sqliteProviders.allSatisfy { $0.provider == report.targetProvider }
        let status = allSessionsMatch && allSQLiteMatch && report.sqliteIntegrity == "ok"
            ? "验证通过"
            : "验证完成：仍有 provider 未同步"
        return snapshot(from: report, status: status)
    }

    func sync(
        codexHome: URL,
        includeArchivedSessions: Bool,
        targetProviderOverride: String?,
        dryRunOnly: Bool
    ) throws -> ProviderSyncSnapshot {
        let initial = try makeReport(codexHome: codexHome, includeArchivedSessions: includeArchivedSessions, targetProviderOverride: targetProviderOverride)
        let backupPath = try createBackup(codexHome: codexHome, sessionFiles: initial.sessionFiles, targetProvider: initial.targetProvider)

        var changedSessionFiles = 0
        var sqliteRowsChanged = 0
        if !dryRunOnly {
            for file in initial.sessionFiles {
                if try rewriteSessionMetaProvider(file: file, targetProvider: initial.targetProvider) {
                    changedSessionFiles += 1
                }
            }
            sqliteRowsChanged = try updateSQLite(codexHome: codexHome, targetProvider: initial.targetProvider)
            try rebuildSessionIndex(codexHome: codexHome)
        }

        var verified = try makeReport(codexHome: codexHome, includeArchivedSessions: includeArchivedSessions, targetProviderOverride: targetProviderOverride)
        var next = snapshot(from: verified, status: dryRunOnly ? "Dry run 完成，已创建备份但未改历史" : "同步完成并已验证")
        next.changedSessionFiles = changedSessionFiles
        next.sqliteRowsChanged = sqliteRowsChanged
        next.lastBackupPath = backupPath.path
        verified = initial
        _ = verified
        return next
    }

    func rollbackLatest(codexHome: URL) throws -> ProviderSyncSnapshot {
        let backup = try latestBackupDirectory()
        try restoreBackup(backup, codexHome: codexHome)
        let report = try makeReport(codexHome: codexHome, includeArchivedSessions: true, targetProviderOverride: nil)
        var next = snapshot(from: report, status: "已从最近备份回滚")
        next.lastBackupPath = backup.path
        return next
    }

    private func makeReport(codexHome: URL, includeArchivedSessions: Bool, targetProviderOverride: String?) throws -> ProviderSyncReport {
        let sessionFiles = findSessionFiles(codexHome: codexHome, includeArchivedSessions: includeArchivedSessions)
        var sessionProviders: [String: Int] = [:]
        var invalidSessionFiles = 0
        for file in sessionFiles {
            guard let provider = try readSessionProvider(file: file) else {
                invalidSessionFiles += 1
                continue
            }
            sessionProviders[provider, default: 0] += 1
        }

        let sqliteProviders = try readSQLiteProviders(codexHome: codexHome)
        let latestSQLite = try latestSQLiteProvider(codexHome: codexHome)
        let newestSession = try newestSessionProvider(in: sessionFiles)
        let configProvider = try configProvider(codexHome: codexHome)
        let targetProvider = targetProviderOverride
            ?? configProvider
            ?? latestSQLite.provider
            ?? newestSession.provider
            ?? "openai"
        let providerSource: String
        if targetProviderOverride != nil {
            providerSource = "手动指定"
        } else if configProvider != nil {
            providerSource = "config.toml"
        } else if latestSQLite.provider != nil {
            providerSource = "最新 SQLite thread"
        } else if newestSession.provider != nil {
            providerSource = "最近 session JSONL"
        } else {
            providerSource = "默认 openai，请确认"
        }

        let indexIDs = try readSessionIndexIDs(codexHome: codexHome)
        return ProviderSyncReport(
            codexHome: codexHome,
            targetProvider: targetProvider,
            providerSource: providerSource,
            sessionFiles: sessionFiles,
            sessionProviders: sessionProviders,
            invalidSessionFiles: invalidSessionFiles,
            sqliteProviders: sqliteProviders,
            sqliteIntegrity: try sqliteIntegrity(codexHome: codexHome),
            latestThreadID: latestSQLite.threadID,
            sessionIndexIDs: indexIDs.ids,
            sessionIndexRows: indexIDs.rows,
            codexRunning: isCodexRunning()
        )
    }

    private func snapshot(from report: ProviderSyncReport, status: String) -> ProviderSyncSnapshot {
        ProviderSyncSnapshot(
            codexHome: CodexDataSource(codexHome: report.codexHome, origin: .defaultHome).displayPath,
            detectedProvider: report.targetProvider,
            providerSource: report.providerSource,
            sessionFilesFound: report.sessionFiles.count,
            sessionProviders: report.sessionProviders
                .map { ProviderSyncProviderCount(provider: $0.key, count: $0.value) }
                .sorted { $0.count == $1.count ? $0.provider < $1.provider : $0.count > $1.count },
            sqliteProviders: report.sqliteProviders
                .map { ProviderSyncSQLiteCount(provider: $0.provider, archived: $0.archived, count: $0.count) }
                .sorted { lhs, rhs in
                    if lhs.archived != rhs.archived { return lhs.archived < rhs.archived }
                    if lhs.count != rhs.count { return lhs.count > rhs.count }
                    return lhs.provider < rhs.provider
                },
            invalidSessionFiles: report.invalidSessionFiles,
            sqliteIntegrity: report.sqliteIntegrity,
            sessionIndexCurrentThreadPresent: report.latestThreadID.map { report.sessionIndexIDs.contains($0) } ?? false,
            sessionIndexRows: report.sessionIndexRows,
            codexRunning: report.codexRunning,
            status: report.codexRunning ? "\(status)，建议退出 Codex 后执行同步" : status,
            isWorking: false
        )
    }

    private func configProvider(codexHome: URL) throws -> String? {
        let config = codexHome.appendingPathComponent("config.toml")
        guard fileManager.fileExists(atPath: config.path) else { return nil }
        let text = try String(contentsOf: config, encoding: .utf8)
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            guard let range = line.range(of: #"^\s*model_provider\s*=\s*"([^"]+)""#, options: .regularExpression) else { continue }
            let match = String(line[range])
            if let valueRange = match.range(of: #""([^"]+)""#, options: .regularExpression) {
                return String(match[valueRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }

    private func findSessionFiles(codexHome: URL, includeArchivedSessions: Bool) -> [URL] {
        var roots = [codexHome.appendingPathComponent("sessions")]
        if includeArchivedSessions {
            roots.append(codexHome.appendingPathComponent("archived_sessions"))
        }
        var files: [URL] = []
        for root in roots where fileManager.fileExists(atPath: root.path) {
            if let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                    files.append(file)
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func newestSessionProvider(in files: [URL]) throws -> (provider: String?, file: URL?) {
        let sorted = files.sorted {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast >
                ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for file in sorted {
            if let provider = try readSessionProvider(file: file) {
                return (provider, file)
            }
        }
        return (nil, nil)
    }

    private func readSessionProvider(file: URL) throws -> String? {
        guard let object = try readFirstLineJSON(file: file),
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any] else {
            return nil
        }
        return payload["model_provider"] as? String
    }

    private func readFirstLineJSON(file: URL) throws -> [String: Any]? {
        guard let firstLine = try readFirstLineData(file: file), !firstLine.isEmpty else { return nil }
        let value = try JSONSerialization.jsonObject(with: firstLine, options: [])
        return value as? [String: Any]
    }

    private func readFirstLineData(file: URL) throws -> Data? {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var buffer = Data()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            guard !chunk.isEmpty else {
                return buffer.isEmpty ? nil : buffer
            }
            if let newline = chunk.firstIndex(of: 0x0A) {
                buffer.append(chunk[..<newline])
                return buffer
            }
            buffer.append(chunk)
        }
    }

    private func rewriteSessionMetaProvider(file: URL, targetProvider: String) throws -> Bool {
        let data = try Data(contentsOf: file)
        let newline = data.firstIndex(of: 0x0A) ?? data.endIndex
        guard newline > data.startIndex else { return false }

        let firstLine = data[data.startIndex..<newline]
        guard var object = try JSONSerialization.jsonObject(with: Data(firstLine), options: []) as? [String: Any],
              object["type"] as? String == "session_meta",
              var payload = object["payload"] as? [String: Any] else {
            return false
        }
        let currentProvider = payload["model_provider"] as? String
        guard currentProvider != targetProvider else { return false }

        payload["model_provider"] = targetProvider
        object["payload"] = payload
        let updatedLine = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var output = Data()
        output.append(updatedLine)
        output.append(0x0A)
        if newline < data.endIndex {
            let restStart = data.index(after: newline)
            output.append(data[restStart..<data.endIndex])
        }
        try output.write(to: file, options: [.atomic])
        return true
    }

    private func readSQLiteProviders(codexHome: URL) throws -> [ProviderSyncSQLiteProvider] {
        let db = codexHome.appendingPathComponent("state_5.sqlite")
        guard fileManager.fileExists(atPath: db.path) else { return [] }
        return try withDatabase(path: db.path, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX) { database in
            try queryRows(
                database: database,
                sql: """
                SELECT model_provider, archived, COUNT(*)
                FROM threads
                GROUP BY model_provider, archived
                ORDER BY archived ASC, COUNT(*) DESC;
                """
            ) { statement in
                ProviderSyncSQLiteProvider(
                    provider: sqliteText(statement, 0) ?? "(missing)",
                    archived: Int(sqlite3_column_int64(statement, 1)),
                    count: Int(sqlite3_column_int64(statement, 2))
                )
            }
        }
    }

    private func latestSQLiteProvider(codexHome: URL) throws -> (provider: String?, threadID: String?) {
        let db = codexHome.appendingPathComponent("state_5.sqlite")
        guard fileManager.fileExists(atPath: db.path) else { return (nil, nil) }
        return try withDatabase(path: db.path, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX) { database in
            try queryRows(
                database: database,
                sql: """
                SELECT model_provider, id
                FROM threads
                WHERE archived = 0
                ORDER BY COALESCE(updated_at_ms, updated_at * 1000) DESC
                LIMIT 1;
                """
            ) { statement in
                (sqliteText(statement, 0), sqliteText(statement, 1))
            }.first ?? (nil, nil)
        }
    }

    private func updateSQLite(codexHome: URL, targetProvider: String) throws -> Int {
        let db = codexHome.appendingPathComponent("state_5.sqlite")
        guard fileManager.fileExists(atPath: db.path) else { return 0 }
        return try withDatabase(path: db.path, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX) { database in
            let changed = try executeBoundUpdate(
                database: database,
                sql: "UPDATE threads SET model_provider = ? WHERE model_provider <> ?;",
                values: [targetProvider, targetProvider]
            )
            try execute(database: database, sql: "PRAGMA wal_checkpoint(FULL);")
            return changed
        }
    }

    private func sqliteIntegrity(codexHome: URL) throws -> String {
        let db = codexHome.appendingPathComponent("state_5.sqlite")
        guard fileManager.fileExists(atPath: db.path) else { return "missing" }
        return try withDatabase(path: db.path, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX) { database in
            try queryRows(database: database, sql: "PRAGMA integrity_check;") { statement in
                sqliteText(statement, 0) ?? "unknown"
            }.first ?? "unknown"
        }
    }

    private func rebuildSessionIndex(codexHome: URL) throws {
        let db = codexHome.appendingPathComponent("state_5.sqlite")
        guard fileManager.fileExists(atPath: db.path) else { return }
        let rows = try withDatabase(path: db.path, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX) { database in
            try queryRows(
                database: database,
                sql: """
                SELECT id, title, COALESCE(updated_at_ms, updated_at * 1000)
                FROM threads
                ORDER BY COALESCE(updated_at_ms, updated_at * 1000) ASC, id ASC;
                """
            ) { statement in
                ProviderSyncThreadIndexRow(
                    id: sqliteText(statement, 0) ?? "",
                    title: sqliteText(statement, 1) ?? "",
                    updatedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 2)) / 1000)
                )
            }.filter { !$0.id.isEmpty }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var output = Data()
        for row in rows {
            let object = [
                "id": row.id,
                "thread_name": row.title,
                "updated_at": formatter.string(from: row.updatedAt)
            ]
            output.append(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            output.append(0x0A)
        }
        let index = codexHome.appendingPathComponent("session_index.jsonl")
        try output.write(to: index, options: [.atomic])
    }

    private func readSessionIndexIDs(codexHome: URL) throws -> (ids: Set<String>, rows: Int) {
        let index = codexHome.appendingPathComponent("session_index.jsonl")
        guard fileManager.fileExists(atPath: index.path) else { return ([], 0) }
        let text = try String(contentsOf: index, encoding: .utf8)
        var ids = Set<String>()
        var rows = 0
        for line in text.split(separator: "\n") {
            rows += 1
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String else {
                continue
            }
            ids.insert(id)
        }
        return (ids, rows)
    }

    private func createBackup(codexHome: URL, sessionFiles: [URL], targetProvider: String) throws -> URL {
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexHistoryRepair/backups", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = root.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)

        try copyIfExists(codexHome.appendingPathComponent("config.toml"), to: backup.appendingPathComponent("config.toml.before"))
        try copyIfExists(codexHome.appendingPathComponent("state_5.sqlite"), to: backup.appendingPathComponent("state_5.sqlite.before"))
        try copyIfExists(codexHome.appendingPathComponent("session_index.jsonl"), to: backup.appendingPathComponent("session_index.jsonl.before"))
        try createSessionTar(files: sessionFiles, destination: backup.appendingPathComponent("session-jsonl.before.tar"))

        let manifest: [String: Any] = [
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "codex_home": codexHome.path,
            "target_provider": targetProvider,
            "session_file_count": sessionFiles.count
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: backup.appendingPathComponent("manifest.json"), options: [.atomic])
        return backup
    }

    private func copyIfExists(_ source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func createSessionTar(files: [URL], destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-C", "/", "-cf", destination.path] + files.map { String($0.path.dropFirst()) }
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "tar failed"
            throw NSError(domain: "CodexTokenBar", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func latestBackupDirectory() throws -> URL {
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexHistoryRepair/backups", isDirectory: true)
        let backups = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        guard let latest = backups
            .filter({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
            .max(by: {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
                    ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }) else {
            throw NSError(domain: "CodexTokenBar", code: 404, userInfo: [NSLocalizedDescriptionKey: "没有可回滚的备份"])
        }
        return latest
    }

    private func restoreBackup(_ backup: URL, codexHome: URL) throws {
        try copyIfExists(backup.appendingPathComponent("config.toml.before"), to: codexHome.appendingPathComponent("config.toml"))
        let state = codexHome.appendingPathComponent("state_5.sqlite")
        try? fileManager.removeItem(at: codexHome.appendingPathComponent("state_5.sqlite-shm"))
        try? fileManager.removeItem(at: codexHome.appendingPathComponent("state_5.sqlite-wal"))
        try copyIfExists(backup.appendingPathComponent("state_5.sqlite.before"), to: state)
        try copyIfExists(backup.appendingPathComponent("session_index.jsonl.before"), to: codexHome.appendingPathComponent("session_index.jsonl"))

        let tar = backup.appendingPathComponent("session-jsonl.before.tar")
        if fileManager.fileExists(atPath: tar.path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-C", "/", "-xf", tar.path]
            let error = Pipe()
            process.standardError = error
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "tar restore failed"
                throw NSError(domain: "CodexTokenBar", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
    }

    private func isCodexRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            guard let name = app.localizedName else { return false }
            return name == "Codex"
        }
    }

    private func withDatabase<T>(path: String, flags: Int32, body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let status = sqlite3_open_v2(path, &database, flags, nil)
        guard status == SQLITE_OK, let database else {
            let message = database.map { sqliteErrorMessage($0) } ?? "Unable to open SQLite database"
            if let database {
                sqlite3_close(database)
            }
            throw NSError(domain: "CodexTokenBar", code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(database) }
        return try body(database)
    }

    private func queryRows<T>(database: OpaquePointer, sql: String, map: (OpaquePointer?) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            throw NSError(domain: "CodexTokenBar", code: Int(prepareStatus), userInfo: [NSLocalizedDescriptionKey: sqliteErrorMessage(database)])
        }
        defer { sqlite3_finalize(statement) }

        var rows: [T] = []
        while true {
            let stepStatus = sqlite3_step(statement)
            if stepStatus == SQLITE_ROW {
                rows.append(try map(statement))
            } else if stepStatus == SQLITE_DONE {
                return rows
            } else {
                throw NSError(domain: "CodexTokenBar", code: Int(stepStatus), userInfo: [NSLocalizedDescriptionKey: sqliteErrorMessage(database)])
            }
        }
    }

    private func execute(database: OpaquePointer, sql: String) throws {
        var error: UnsafeMutablePointer<Int8>?
        let status = sqlite3_exec(database, sql, nil, nil, &error)
        guard status == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? sqliteErrorMessage(database)
            sqlite3_free(error)
            throw NSError(domain: "CodexTokenBar", code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func executeBoundUpdate(database: OpaquePointer, sql: String, values: [String]) throws -> Int {
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            throw NSError(domain: "CodexTokenBar", code: Int(prepareStatus), userInfo: [NSLocalizedDescriptionKey: sqliteErrorMessage(database)])
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, sqliteTransient)
        }
        let before = sqlite3_total_changes(database)
        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_DONE else {
            throw NSError(domain: "CodexTokenBar", code: Int(stepStatus), userInfo: [NSLocalizedDescriptionKey: sqliteErrorMessage(database)])
        }
        return Int(sqlite3_total_changes(database) - before)
    }

    private func sqliteText(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private func sqliteErrorMessage(_ database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else { return "SQLite error" }
        return String(cString: message)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
