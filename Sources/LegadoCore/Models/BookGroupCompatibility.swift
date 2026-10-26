import Foundation

public enum BookGroupCompatibilityError: LocalizedError {
    case capacity
    case invalidIdentifier(Int64)
    case invalidName

    public var errorDescription: String? {
        switch self {
        case .capacity: return "自定义分组最多支持 63 组，原数据已保留"
        case .invalidIdentifier(let id): return "备份中的分组编号无效：\(id)"
        case .invalidName: return "分组名称不能为空"
        }
    }
}

/// Android BookGroup.groupId is a positive single-bit Long; Book.group is their union.
/// Legacy iOS IDs were arbitrary timestamps and must be converted as identities, not bits.
public enum BookGroupCompatibility {
    public struct Migration: Codable {
        public var groups: [BookGroup]
        public var books: [Book]
        public var legacyIDs: [String: Int64]
    }

    public struct Merge {
        public var groups: [BookGroup]
        public var books: [Book]
    }

    public static func isSingleBit(_ id: Int64) -> Bool { id > 0 && (id & (id - 1)) == 0 }

    public static func nextIdentifier(in groups: [BookGroup]) -> Int64? {
        let used = groups.filter { $0.groupId > 0 }.reduce(Int64(0)) { $0 | $1.groupId }
        return (0..<63).map { Int64(1) << $0 }.first { used & $0 == 0 }
    }

    public static func migrateLegacy(groups: [BookGroup], books: [Book]) throws -> Migration {
        var definitions = unique(groups)
        let known = Set(definitions.map(\.groupId))
        let nativeMask = definitions.filter { isSingleBit($0.groupId) }.reduce(Int64(0)) { $0 | $1.groupId }
        for id in Set(books.map(\.group)).sorted() where id > 0 && !known.contains(id) {
            if nativeMask != 0, id & ~nativeMask == 0 { continue }
            definitions.append(BookGroup(groupId: id, groupName: "分组 \(id)", order: definitions.count))
        }
        var occupied = definitions.filter { isSingleBit($0.groupId) }
        var mapping: [String: Int64] = [:]
        for index in definitions.indices where definitions[index].groupId > 0 {
            let old = definitions[index].groupId
            let id: Int64
            if isSingleBit(old) { id = old }
            else {
                guard let available = nextIdentifier(in: occupied) else { throw BookGroupCompatibilityError.capacity }
                id = available
                occupied.append(BookGroup(groupId: id))
            }
            if old != id { mapping[String(old)] = id }
            definitions[index].groupId = id
        }
        let migrated = books.map { original -> Book in
            var book = original
            book.group = mapping[String(original.group)] ?? original.group
            return book
        }
        return Migration(groups: definitions, books: migrated, legacyIDs: mapping)
    }

    /// Preserve local group identities when another device reuses the same bit for a
    /// different group. Remap only restored books; existing books retain their membership.
    public static func mergeAndroid(groups incoming: [BookGroup], books: [Book],
                                    into local: [BookGroup]) throws -> Merge {
        var imported = unique(incoming.filter { $0.groupId != BookGroup.idNet })
        for group in imported where group.groupId > 0 && !isSingleBit(group.groupId) {
            throw BookGroupCompatibilityError.invalidIdentifier(group.groupId)
        }
        let declared = imported.filter { $0.groupId > 0 }.reduce(Int64(0)) { $0 | $1.groupId }
        let unknown = books.filter { $0.group > 0 }.reduce(Int64(0)) { $0 | $1.group } & ~declared
        for bit in (0..<63).map({ Int64(1) << $0 }) where unknown & bit != 0 {
            imported.append(BookGroup(groupId: bit, groupName: "导入分组 \(bit)", order: imported.count))
        }
        var result = unique(local)
        var mapping: [Int64: Int64] = [:]
        var destinations = Set<Int64>()
        for var group in imported {
            if group.groupId <= 0 {
                if let index = result.firstIndex(where: { $0.groupId == group.groupId }) { result[index] = group }
                else { result.append(group) }
                continue
            }
            let original = group.groupId
            let match = result.firstIndex {
                $0.groupId > 0 && $0.groupName == group.groupName && !destinations.contains($0.groupId)
            }
            if let index = match {
                group.groupId = result[index].groupId
                result[index] = group
            } else if !result.contains(where: { $0.groupId == original }) {
                result.append(group)
            } else {
                guard let available = nextIdentifier(in: result) else { throw BookGroupCompatibilityError.capacity }
                group.groupId = available
                result.append(group)
            }
            mapping[original] = group.groupId
            destinations.insert(group.groupId)
        }
        let restored = books.map { original -> Book in
            var book = original
            guard original.group > 0 else { return book }
            book.group = mapping.reduce(Int64(0)) { mask, pair in original.group & pair.key != 0 ? mask | pair.value : mask }
            return book
        }
        return Merge(groups: result, books: restored)
    }

    private static func unique(_ groups: [BookGroup]) -> [BookGroup] {
        var result: [BookGroup] = []
        for group in groups {
            if let index = result.firstIndex(where: { $0.groupId == group.groupId }) { result[index] = group }
            else { result.append(group) }
        }
        return result
    }
}
