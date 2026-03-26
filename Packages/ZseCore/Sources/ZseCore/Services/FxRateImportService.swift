import Foundation
import ZIPFoundation

struct FxRateImportService {
    private let fxRateRepository: FxRateRepository
    private let workbookURL = URL(string: "https://www.mnb.hu/Root/ExchangeRate/arfolyam.xlsx")!
    private let dailyRatesPageURL = URL(string: "https://www.mnb.hu/arfolyamok")!

    init(fxRateRepository: FxRateRepository) {
        self.fxRateRepository = fxRateRepository
    }

    func refreshLatestRelevantRatesIfPossible() async throws -> String? {
        let relevantCurrencies = try fxRateRepository.relevantCurrencyCodes()
        guard !relevantCurrencies.isEmpty else {
            return nil
        }

        let latestRates: LatestRateSource

        do {
            latestRates = try await loadLatestWorkbookRates()
        } catch {
            latestRates = try await loadLatestHTMLRates()
        }

        let ratesToStore = makeRatesToStore(
            relevantCurrencies: relevantCurrencies,
            latestRates: latestRates
        )

        try fxRateRepository.upsertRates(ratesToStore)
        return latestRates.rateDate
    }

    private func loadLatestWorkbookRates() async throws -> LatestRateSource {
        let (temporaryURL, _) = try await URLSession.shared.download(from: workbookURL)
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let sharedStringsXML = try archiveEntryData(
            from: temporaryURL,
            entryPath: "xl/sharedStrings.xml"
        )
        let sheetXML = try archiveEntryData(
            from: temporaryURL,
            entryPath: "xl/worksheets/sheet1.xml"
        )

        let sharedStrings = try SharedStringsParser.parse(data: sharedStringsXML)
        let latestSheetRow = try LatestWorksheetRowParser.parse(
            data: sheetXML,
            sharedStrings: sharedStrings
        )

        let valuesByCurrency = latestSheetRow.columnByCurrency.reduce(into: [String: Double]()) { result, item in
            guard let rawRate = latestSheetRow.valuesByColumn[item.value] else {
                return
            }

            let unit = latestSheetRow.unitsByColumn[item.value] ?? 1.0
            guard unit > 0 else {
                return
            }

            result[item.key] = rawRate / unit
        }

        return LatestRateSource(
            rateDate: latestSheetRow.rateDate,
            valuesByCurrency: valuesByCurrency
        )
    }

    private func loadLatestHTMLRates() async throws -> LatestRateSource {
        let (data, _) = try await URLSession.shared.data(from: dailyRatesPageURL)
        let html = try decodeHTML(data)
        return try DailyRatesHTMLParser.parse(html: html)
    }

    private func decodeHTML(_ data: Data) throws -> String {
        if let html = String(data: data, encoding: .utf8) {
            return html
        }

        if let html = String(data: data, encoding: .isoLatin2) {
            return html
        }

        throw FxRateImportError.htmlParseFailed("Could not decode the MNB rates page.")
    }

    private func makeRatesToStore(
        relevantCurrencies: Set<String>,
        latestRates: LatestRateSource
    ) -> [FxRate] {
        let downloadedAt = FxRate.makeTimestamp()
        var ratesToStore: [FxRate] = []

        for currencyCode in relevantCurrencies.sorted() {
            if currencyCode == "HUF" {
                ratesToStore.append(
                    FxRate(
                        rateDate: latestRates.rateDate,
                        currencyCode: "HUF",
                        hufRate: 1.0,
                        downloadedAt: downloadedAt
                    )
                )
                continue
            }

            guard let hufRate = latestRates.valuesByCurrency[currencyCode] else {
                continue
            }

            ratesToStore.append(
                FxRate(
                    rateDate: latestRates.rateDate,
                    currencyCode: currencyCode,
                    hufRate: hufRate,
                    downloadedAt: downloadedAt
                )
            )
        }

        return ratesToStore
    }

    private func archiveEntryData(
        from archiveURL: URL,
        entryPath: String
    ) throws -> Data {
        guard let archive = Archive(url: archiveURL, accessMode: .read) else {
            throw FxRateImportError.unzipFailed("The downloaded workbook is not a readable ZIP archive.")
        }

        guard let entry = archive[entryPath] else {
            throw FxRateImportError.unzipFailed("Missing workbook entry: \(entryPath)")
        }

        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }
}

private struct LatestRateSource {
    let rateDate: String
    let valuesByCurrency: [String: Double]
}

private struct LatestWorksheetRow {
    let rateDate: String
    let columnByCurrency: [String: String]
    let unitsByColumn: [String: Double]
    let valuesByColumn: [String: Double]
}

private enum DailyRatesHTMLParser {
    static func parse(html: String) throws -> LatestRateSource {
        let rateDate = try parseRateDate(html)
        let rowPattern = #"<tr>\s*<td class="fw-b">([A-Z]{3})</td>\s*<td>[^<]*</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*</tr>"#
        let regex = try NSRegularExpression(pattern: rowPattern)
        let nsHTML = html as NSString
        let matches = regex.matches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        )

        var valuesByCurrency: [String: Double] = [:]

        for match in matches where match.numberOfRanges == 4 {
            let currencyCode = nsHTML.substring(with: match.range(at: 1))
            let unitText = nsHTML.substring(with: match.range(at: 2))
            let valueText = nsHTML.substring(with: match.range(at: 3))

            guard let unit = Double(unitText.replacingOccurrences(of: ",", with: ".")),
                  unit > 0,
                  let rawValue = parseHungarianDecimal(valueText) else {
                continue
            }

            valuesByCurrency[currencyCode] = rawValue / unit
        }

        guard !valuesByCurrency.isEmpty else {
            throw FxRateImportError.htmlParseFailed("Could not find any FX rows on the MNB rates page.")
        }

        return LatestRateSource(rateDate: rateDate, valuesByCurrency: valuesByCurrency)
    }

    private static func parseRateDate(_ html: String) throws -> String {
        let pattern = #"Napi árfolyamok:\s*([0-9]{4})\.\s*([[:alpha:]áéíóöőúüű]+)\s*([0-9]{1,2})\."#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let nsHTML = html as NSString
        let searchRange = NSRange(location: 0, length: nsHTML.length)

        guard let match = regex.firstMatch(in: html, range: searchRange),
              match.numberOfRanges == 4 else {
            throw FxRateImportError.htmlParseFailed("Could not find the MNB rate date on the rates page.")
        }

        let year = nsHTML.substring(with: match.range(at: 1))
        let monthName = nsHTML.substring(with: match.range(at: 2)).lowercased()
        let dayText = nsHTML.substring(with: match.range(at: 3))

        guard let month = monthNumberByHungarianName[monthName],
              let day = Int(dayText) else {
            throw FxRateImportError.htmlParseFailed("Could not parse the MNB rate date from the rates page.")
        }

        return String(format: "%@-%02d-%02d", year, month, day)
    }

    private static func parseHungarianDecimal(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }

    private static let monthNumberByHungarianName: [String: Int] = [
        "január": 1,
        "február": 2,
        "március": 3,
        "április": 4,
        "május": 5,
        "június": 6,
        "július": 7,
        "augusztus": 8,
        "szeptember": 9,
        "október": 10,
        "november": 11,
        "december": 12
    ]
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var currentText = ""
    private var isInsideTextNode = false

    static func parse(data: Data) throws -> [String] {
        let parserDelegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else {
            throw parser.parserError ?? FxRateImportError.sharedStringsParseFailed
        }
        return parserDelegate.strings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "t" {
            currentText = ""
            isInsideTextNode = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideTextNode {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "t" {
            isInsideTextNode = false
        } else if elementName == "si" {
            strings.append(currentText)
            currentText = ""
        }
    }
}

private final class LatestWorksheetRowParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var currentRowIndex: Int?
    private var currentCellReference = ""
    private var currentCellType: String?
    private var currentValue = ""
    private var currentRowValues: [String: String] = [:]
    private var headerByColumn: [String: String] = [:]
    private var unitByColumn: [String: Double] = [:]
    private var latestRateDate = ""
    private var latestValuesByColumn: [String: Double] = [:]
    private var isInsideValue = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(data: Data, sharedStrings: [String]) throws -> LatestWorksheetRow {
        let parserDelegate = LatestWorksheetRowParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else {
            throw parser.parserError ?? FxRateImportError.sheetParseFailed
        }

        return LatestWorksheetRow(
            rateDate: parserDelegate.latestRateDate,
            columnByCurrency: Dictionary(
                uniqueKeysWithValues: parserDelegate.headerByColumn.map { ($0.value, $0.key) }
            ),
            unitsByColumn: parserDelegate.unitByColumn,
            valuesByColumn: parserDelegate.latestValuesByColumn
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "row":
            currentRowIndex = Int(attributeDict["r"] ?? "")
            currentRowValues = [:]
        case "c":
            currentCellReference = attributeDict["r"] ?? ""
            currentCellType = attributeDict["t"]
        case "v":
            currentValue = ""
            isInsideValue = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideValue {
            currentValue += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "v":
            isInsideValue = false
        case "c":
            let column = columnLetters(from: currentCellReference)
            currentRowValues[column] = resolvedCellValue(rawValue: currentValue, type: currentCellType)
            currentCellReference = ""
            currentCellType = nil
            currentValue = ""
        case "row":
            finalizeRow()
            currentRowIndex = nil
            currentRowValues = [:]
        default:
            break
        }
    }

    private func finalizeRow() {
        guard let currentRowIndex else {
            return
        }

        switch currentRowIndex {
        case 1:
            headerByColumn = currentRowValues
        case 2:
            unitByColumn = currentRowValues.reduce(into: [:]) { result, item in
                let normalized = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
                result[item.key] = Double(normalized) ?? 1.0
            }
        default:
            guard let excelSerialText = currentRowValues["A"],
                  let excelSerial = Double(excelSerialText) else {
                return
            }

            latestRateDate = Self.excelDateFormatter.string(from: excelDate(from: excelSerial))
            latestValuesByColumn = currentRowValues.reduce(into: [:]) { result, item in
                guard item.key != "A",
                      let numericValue = Double(item.value) else {
                    return
                }
                result[item.key] = numericValue
            }
        }
    }

    private func resolvedCellValue(rawValue: String, type: String?) -> String {
        if let sharedStringIndex = Int(rawValue),
           sharedStringIndex >= 0,
           sharedStringIndex < sharedStrings.count,
           (type == "s" || currentRowIndex == 1 || currentRowIndex == 2) {
            return sharedStrings[sharedStringIndex]
        }

        return rawValue
    }

    private func columnLetters(from cellReference: String) -> String {
        String(cellReference.prefix { $0.isLetter })
    }

    private func excelDate(from serial: Double) -> Date {
        let baseDateComponents = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 1899,
            month: 12,
            day: 30
        )
        let baseDate = baseDateComponents.date ?? Date(timeIntervalSince1970: 0)
        return baseDate.addingTimeInterval(serial * 86400)
    }

    private static let excelDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum FxRateImportError: Error, LocalizedError {
    case unzipFailed(String)
    case sharedStringsParseFailed
    case sheetParseFailed
    case htmlParseFailed(String)

    var errorDescription: String? {
        switch self {
        case .unzipFailed(let message):
            return "Could not extract the MNB workbook: \(message)"
        case .sharedStringsParseFailed:
            return "Could not parse MNB shared strings."
        case .sheetParseFailed:
            return "Could not parse MNB worksheet data."
        case .htmlParseFailed(let message):
            return "Could not parse MNB HTML rates page: \(message)"
        }
    }
}
