import Foundation
import SQLite3

/// A value bound to a statement.
enum SQLiteValue {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

/// One row of a result.
struct SQLiteRow {
    fileprivate let statement: OpaquePointer

    func integer(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    func real(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func text(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
    func blob(_ column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}

/// A thin wrapper over the C interface of SQLite. It is used from one actor only, so it holds the handle without a lock.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var opened: OpaquePointer?
        guard sqlite3_open_v2(path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close(opened)
            throw TrackStoreError.cannotOpen(message)
        }
        handle = opened
    }

    deinit { sqlite3_close(handle) }

    private var message: String { handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed" }

    /// Runs statements that give no rows.
    func execute(_ sql: String, _ values: [SQLiteValue] = []) throws {
        try run(sql, values) { _ in }
    }

    /// Runs a statement and calls `row` for each row of the result.
    func run(_ sql: String, _ values: [SQLiteValue] = [], row: (SQLiteRow) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TrackStoreError.sqlite(message)
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .integer(let number): result = sqlite3_bind_int64(statement, index, number)
            case .real(let number): result = sqlite3_bind_double(statement, index, number)
            case .text(let text): result = sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .blob(let data):
                result = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), Self.transient) }
            }
            guard result == SQLITE_OK else { throw TrackStoreError.sqlite(message) }
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try row(SQLiteRow(statement: statement))
            case SQLITE_DONE: return
            default: throw TrackStoreError.sqlite(message)
            }
        }
    }

    /// Runs `body` in a transaction: all of it or none of it.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// SQLite copies the value at once, so the memory of the Swift value may go.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
