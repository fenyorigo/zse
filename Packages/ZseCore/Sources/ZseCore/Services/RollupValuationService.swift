import Foundation

struct RollupValuationService {
    private let fxRateRepository: FxRateRepository

    init(fxRateRepository: FxRateRepository) {
        self.fxRateRepository = fxRateRepository
    }

    func convert(
        amount: Double,
        from sourceCurrency: String,
        to targetCurrency: String,
        valuationDate: String? = nil
    ) throws -> Double? {
        guard sourceCurrency != targetCurrency else {
            return amount
        }

        let resolvedDate = try valuationDate ?? fxRateRepository.latestStoredRateDate()
        guard let resolvedDate else {
            return nil
        }

        let sourceRate = try hufRate(for: sourceCurrency, onOrBefore: resolvedDate)
        let targetRate = try hufRate(for: targetCurrency, onOrBefore: resolvedDate)

        guard let sourceRate, let targetRate else {
            return nil
        }

        if targetCurrency == "HUF" {
            return amount * sourceRate
        }

        if sourceCurrency == "HUF" {
            return amount / targetRate
        }

        return amount * sourceRate / targetRate
    }

    func latestValuationDate() throws -> String? {
        try fxRateRepository.latestStoredRateDate()
    }

    private func hufRate(
        for currencyCode: String,
        onOrBefore rateDate: String
    ) throws -> Double? {
        try fxRateRepository.hufRate(for: currencyCode, onOrBefore: rateDate)
    }
}
