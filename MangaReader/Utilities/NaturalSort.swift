import Foundation

enum NaturalSort {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedStandardCompare(rhs)
    }

    static func sorted<T>(_ values: [T], by key: (T) -> String) -> [T] {
        values.sorted { compare(key($0), key($1)) == .orderedAscending }
    }
}
