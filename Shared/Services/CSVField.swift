//
//  CSVField.swift
//  NALI Migraine Log
//
//  One CSV cell encoder for every export (iOS share sheet, macOS
//  fileExporter) so quoting and injection handling can't drift apart.
//

import Foundation

enum CSVField {
    /// Characters that make a spreadsheet treat a cell as a formula when
    /// the file is opened in Excel, Numbers or Sheets. A note like
    /// `=HYPERLINK(...)` typed into the app would otherwise execute on
    /// whoever opens the export.
    private static let formulaLeaders: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    /// RFC 4180 cell: newlines collapsed to spaces, embedded quotes doubled,
    /// wrapped in quotes when the content needs it, and formula leaders
    /// neutralised with a leading apostrophe.
    ///
    /// Numbers and other app-generated values pass through `escape` too so
    /// callers never have to decide which path a field belongs on; a bare
    /// `7` or `2025-11-28 09:00` is returned unchanged.
    static func escape(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        if let first = value.first, formulaLeaders.contains(first), !looksNumeric(value) {
            value = "'" + value
        }

        if value.contains(",") || value.contains("\"") || value.hasPrefix(" ") || value.hasSuffix(" ") {
            value = "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    /// Joins already-escaped cells into one record line.
    static func row(_ cells: [String]) -> String {
        cells.map(escape).joined(separator: ",") + "\n"
    }

    /// `-3.15` is a legitimate signed number (pressure change), not a
    /// formula; only prefix when the text after the sign isn't numeric.
    private static func looksNumeric(_ value: String) -> Bool {
        guard let first = value.first, first == "-" || first == "+" else { return false }
        let body = value.dropFirst()
        return !body.isEmpty && Double(body) != nil
    }
}
