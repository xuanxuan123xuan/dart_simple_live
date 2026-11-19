import Foundation

struct SyncChunk {
    let index: Int
    let total: Int
    let start: Int
    let end: Int
    let items: Int

    init(fields: [String: Any]) throws {
        func number(_ key: String, default fallback: Int) throws -> Int {
            guard let value = fields[key] else { return fallback }
            guard let text = value as? String ?? (value as? NSNumber)?.stringValue,
                  let result = Int(text), result >= 0 else { throw SyncError.invalidChunk }
            return result
        }
        index = try number("chunkIndex", default: 1)
        total = try number("chunkTotal", default: 1)
        start = try number("itemStart", default: 0)
        end = try number("itemEnd", default: 0)
        items = try number("itemTotal", default: 0)
        guard (1...1024).contains(total), (1...total).contains(index),
              start <= end, end <= items else { throw SyncError.invalidChunk }
    }
}

/// Dart sends sequential chunks and marks overwrite on the first chunk only.
struct SyncChunks {
    enum Result {
        case partial(index: Int, total: Int)
        case complete(rows: [Any], overwrite: Bool)
    }

    private struct Transfer {
        let total: Int
        let items: Int
        let overwrite: Bool
        var nextIndex: Int
        var rows: [Any]
        var bytes: Int
        var lastUpdate: Date
    }

    private var transfers: [String: Transfer] = [:]

    mutating func discard(_ key: String) { transfers[key] = nil }

    mutating func receive(_ chunk: SyncChunk, data: Data, overwrite: Bool, key: String,
                          now: Date = Date()) throws -> Result {
        transfers = transfers.filter { now.timeIntervalSince($0.value.lastUpdate) < 45 }
        do {
            guard data.count <= SyncProfile.maxBytes else { throw SyncError.tooLarge }
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                throw SyncError.invalidChunk
            }
            if chunk.total == 1 {
                guard chunk.start == 0, chunk.items == 0 || (chunk.end == chunk.items && rows.count == chunk.items) else {
                    throw SyncError.invalidChunk
                }
                discard(key)
                return .complete(rows: rows, overwrite: overwrite)
            }
            guard chunk.end - chunk.start == rows.count, !rows.isEmpty,
                  (chunk.index == chunk.total) == (chunk.end == chunk.items) else {
                throw SyncError.invalidChunk
            }
            var transfer: Transfer
            if chunk.index == 1 {
                guard chunk.start == 0, transfers[key] != nil || transfers.count < 4 else {
                    throw SyncError.invalidChunk
                }
                transfer = Transfer(total: chunk.total, items: chunk.items, overwrite: overwrite,
                                    nextIndex: 1, rows: [], bytes: 0, lastUpdate: now)
            } else {
                guard let previous = transfers.removeValue(forKey: key) else { throw SyncError.incompleteTransfer }
                transfer = previous
                guard !overwrite else { throw SyncError.invalidChunk }
            }
            guard chunk.total == transfer.total, chunk.items == transfer.items,
                  chunk.index == transfer.nextIndex, chunk.start == transfer.rows.count else {
                throw SyncError.invalidChunk
            }
            transfer.bytes += data.count
            guard transfer.bytes <= SyncProfile.maxBytes else { throw SyncError.tooLarge }
            transfer.rows.append(contentsOf: rows)
            if chunk.index == chunk.total {
                return .complete(rows: transfer.rows, overwrite: transfer.overwrite)
            }
            transfer.nextIndex += 1
            transfer.lastUpdate = now
            transfers[key] = transfer
            return .partial(index: chunk.index, total: chunk.total)
        } catch {
            discard(key)
            throw error
        }
    }
}
