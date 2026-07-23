import Foundation

struct PricingIndexResult: Sendable {
    let factors: [String: Double]
    let directMarketCount: Int
    let sourceSummary: String
}

struct PricingIndexService: Sendable {
    private let worldBankURL = URL(string: "https://api.worldbank.org/v2/country/all/indicator/PA.NUS.PPP;PA.NUS.FCRF?format=json&per_page=20000&date=2020:2026&source=2")!
    private let bigMacURL = URL(string: "https://raw.githubusercontent.com/TheEconomist/big-mac-data/master/output-data/big-mac-full-index.csv")!
    private let netflixURL = URL(string: "https://raw.githubusercontent.com/tompec/netflix-prices/main/data/latest.json")!

    func factors(for index: PricingIndex) async throws -> PricingIndexResult {
        let worldwide = try await fetchWorldwidePPP()
        switch index {
        case .worldwidePPP:
            return PricingIndexResult(factors: worldwide, directMarketCount: worldwide.count, sourceSummary: "World Bank · " + String(worldwide.count) + " markets")
        case .bigMac:
            let direct = try await fetchBigMac()
            return PricingIndexResult(
                factors: worldwide.merging(direct) { _, latest in latest },
                directMarketCount: direct.count,
                sourceSummary: "The Economist Big Mac · " + String(direct.count) + " direct markets · World Bank fallback"
            )
        case .netflix:
            let direct = try await fetchNetflix()
            return PricingIndexResult(
                factors: worldwide.merging(direct) { _, latest in latest },
                directMarketCount: direct.count,
                sourceSummary: "Netflix Standard plan · " + String(direct.count) + " direct markets · World Bank fallback"
            )
        }
    }

    private func fetchWorldwidePPP() async throws -> [String: Double] {
        let response = try await HTTPTransport.send(url: worldBankURL, method: "GET", headers: ["Accept": "application/json"])
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [Any], root.count > 1,
              let rows = root[1] as? [[String: Any]] else { throw APIError.invalidResponse }
        var values: [String: [String: (year: Int, value: Double)]] = [:]
        for row in rows {
            guard let indicator = (row["indicator"] as? [String: Any])?["id"] as? String,
                  let country = row["countryiso3code"] as? String,
                  country.count == 3,
                  let year = Int(row["date"] as? String ?? ""),
                  let number = (row["value"] as? NSNumber)?.doubleValue else { continue }
            let existing = values[country]?[indicator]
            if existing == nil || year > existing!.year { values[country, default: [:]][indicator] = (year, number) }
        }
        var result: [String: Double] = ["US": 1]
        for (iso3, indicators) in values {
            guard let ppp = indicators["PA.NUS.PPP"], let exchange = indicators["PA.NUS.FCRF"], exchange.value > 0,
                  let iso2 = iso2(fromISO3: iso3) else { continue }
            result[iso2] = normalized(ppp.value / exchange.value)
        }
        guard result.count > 20 else { throw APIError.unsupported("The World Bank PPP dataset did not return enough current markets.") }
        return result
    }

    private func fetchBigMac() async throws -> [String: Double] {
        let response = try await HTTPTransport.send(url: bigMacURL, method: "GET", headers: ["Accept": "text/csv"])
        guard let text = String(data: response.data, encoding: .utf8) else { throw APIError.invalidResponse }
        let lines = text.split(whereSeparator: \Character.isNewline).map(String.init)
        guard let header = lines.first.map(csvFields),
              let dateIndex = header.firstIndex(of: "date"),
              let codeIndex = header.firstIndex(of: "iso_a3"),
              let priceIndex = header.firstIndex(of: "dollar_price") else { throw APIError.invalidResponse }
        var newestDate = ""
        var latest: [(String, Double)] = []
        for line in lines.dropFirst() {
            let fields = csvFields(line)
            guard fields.count > max(dateIndex, codeIndex, priceIndex), let price = Double(fields[priceIndex]) else { continue }
            let date = fields[dateIndex]
            if date > newestDate { newestDate = date; latest.removeAll() }
            if date == newestDate { latest.append((fields[codeIndex], price)) }
        }
        guard let usPrice = latest.first(where: { $0.0 == "USA" })?.1, usPrice > 0 else { throw APIError.invalidResponse }
        return Dictionary(uniqueKeysWithValues: latest.compactMap { iso3, price in
            iso2(fromISO3: iso3).map { ($0, normalized(price / usPrice)) }
        })
    }

    private func fetchNetflix() async throws -> [String: Double] {
        struct Plan: Decodable { let name: String; let price_usd: Double? }
        struct Country: Decodable { let country_code: String; let plans: [Plan] }
        let response = try await HTTPTransport.send(url: netflixURL, method: "GET", headers: ["Accept": "application/json"])
        let countries = try JSONDecoder().decode([Country].self, from: response.data)
        func standard(_ country: Country) -> Double? {
            country.plans.first(where: { $0.name == "standard" })?.price_usd
        }
        guard let us = countries.first(where: { $0.country_code == "US" }).flatMap(standard), us > 0 else { throw APIError.invalidResponse }
        return Dictionary(uniqueKeysWithValues: countries.compactMap { country in
            guard let price = standard(country), price > 0 else { return nil }
            return (country.country_code, normalized(price / us))
        })
    }

    private func normalized(_ value: Double) -> Double { min(1, max(0.1, value)) }
}

func iso2(fromISO3 iso3: String) -> String? {
    let value = Locale(identifier: "en_\(iso3)").region?.identifier
    return value?.count == 2 ? value : nil
}

func countryName(for code: String) -> String {
    Locale.current.localizedString(forRegionCode: code) ?? code
}

func flag(for code: String) -> String {
    code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
}

private func csvFields(_ line: String) -> [String] {
    var result: [String] = []
    var field = ""
    var quoted = false
    let characters = Array(line)
    var index = 0
    while index < characters.count {
        let character = characters[index]
        if character == "\"" {
            if quoted, index + 1 < characters.count, characters[index + 1] == "\"" { field.append("\""); index += 1 }
            else { quoted.toggle() }
        } else if character == ",", !quoted {
            result.append(field); field = ""
        } else { field.append(character) }
        index += 1
    }
    result.append(field)
    return result
}
