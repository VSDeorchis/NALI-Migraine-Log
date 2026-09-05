//
//  CSVFieldTests.swift
//  NALI Migraine LogTests
//

import Foundation
import Testing
@testable import NALI_Migraine_Log

@Suite("CSVField")
struct CSVFieldTests {

    @Test("Plain values pass through unchanged")
    func plain() {
        #expect(CSVField.escape("Frontal") == "Frontal")
        #expect(CSVField.escape("7") == "7")
        #expect(CSVField.escape("2025-11-28 09:00") == "2025-11-28 09:00")
        #expect(CSVField.escape("") == "")
        #expect(CSVField.escape("Yes") == "Yes")
    }

    @Test("Commas and quotes trigger RFC 4180 quoting with doubled inner quotes")
    func quoting() {
        #expect(CSVField.escape("Home, upstairs") == "\"Home, upstairs\"")
        #expect(CSVField.escape("said \"ouch\"") == "\"said \"\"ouch\"\"\"")
        #expect(CSVField.escape("a,\"b\"") == "\"a,\"\"b\"\"\"")
    }

    @Test("Newlines are flattened so one entry stays one line")
    func newlines() {
        #expect(CSVField.escape("line one\nline two") == "line one line two")
        #expect(CSVField.escape("crlf\r\nhere") == "crlf here")
        #expect(CSVField.escape("cr\rhere") == "cr here")
        #expect(!CSVField.row(["a\nb", "c"]).dropLast().contains("\n"))
    }

    @Test("Formula leaders are neutralised so a note can't execute in a spreadsheet")
    func formulaInjection() {
        #expect(CSVField.escape("=HYPERLINK(\"http://evil\",\"click\")") == "\"'=HYPERLINK(\"\"http://evil\"\",\"\"click\"\")\"")
        #expect(CSVField.escape("=1+1") == "'=1+1")
        #expect(CSVField.escape("@SUM(A1)") == "'@SUM(A1)")
        #expect(CSVField.escape("+cmd|' /C calc'!A0") == "'+cmd|' /C calc'!A0")
        #expect(CSVField.escape("-2+3+cmd|' /C calc'!A0") == "'-2+3+cmd|' /C calc'!A0")
        #expect(CSVField.escape("\tX") == "'\tX")
    }

    @Test("Signed numbers such as a negative pressure change are not treated as formulas")
    func signedNumbersUntouched() {
        #expect(CSVField.escape("-3.15") == "-3.15")
        #expect(CSVField.escape("+2") == "+2")
        #expect(CSVField.escape("-0.5") == "-0.5")
        #expect(CSVField.escape("-") == "'-")
    }

    @Test("Leading or trailing whitespace is preserved through quoting")
    func whitespaceEdges() {
        #expect(CSVField.escape(" padded ") == "\" padded \"")
    }

    @Test("Row joins escaped cells and terminates with a newline")
    func row() {
        #expect(CSVField.row(["a", "b,c", "=x"]) == "a,\"b,c\",'=x\n")
        #expect(CSVField.row([]) == "\n")
    }

    @Test("Unicode is passed through byte-for-byte")
    func unicode() {
        let text = "Migräne — très forte 🤕"
        #expect(CSVField.escape(text) == text)
    }
}
