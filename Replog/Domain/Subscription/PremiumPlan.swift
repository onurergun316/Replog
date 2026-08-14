//
//  PremiumPlan.swift
//  Replog
//
//  The two things you can buy, and the arithmetic behind what the paywall claims.
//
//  Deliberately free of StoreKit. The product identifiers and the display order live here as
//  plain values so the paywall's layout, the Profile status strings and their tests all work
//  without a store connection; `SubscriptionStore` is the only type that turns these into
//  real `Product`s.
//
//  **No price is written down in this file, or anywhere else in the app.** Every amount the
//  athlete sees comes from `Product.displayPrice` in their own storefront and currency, and
//  the "SAVE 49%" badge is computed from the two real prices by `PremiumPricing`. That is
//  App Store guideline 3.1.2(c), and it is also the only way the paywall stays honest if the
//  price is ever changed in App Store Connect without a new build.
//

import Foundation

/// A purchasable term. Declared yearly-first because that is the paywall's display order:
/// it is the better deal and the only one carrying a free trial.
nonisolated enum PremiumTerm: String, CaseIterable, Identifiable, Sendable {
    case yearly
    case monthly

    var id: String { rawValue }

    /// The App Store product identifier. Must match App Store Connect exactly, and must never
    /// change once shipped — a receipt names the product by this string.
    var productID: String {
        switch self {
        case .yearly:  return "test.Grewyn.premium.yearly"
        case .monthly: return "test.Grewyn.premium.monthly"
        }
    }

    /// Title on the paywall row and in the Profile status line.
    var displayName: String {
        switch self {
        case .yearly:  return "Yearly"
        case .monthly: return "Monthly"
        }
    }

    /// The billing period as a noun, for "$29.99 per year".
    var periodNoun: String {
        switch self {
        case .yearly:  return "year"
        case .monthly: return "month"
        }
    }

    /// Whether this term is *intended* to carry an introductory free trial.
    ///
    /// This is our intent, not the truth — StoreKit grants whatever App Store Connect is
    /// configured with. The paywall always renders the offer it actually finds on the
    /// product; this exists so a test can assert the shipped configuration still agrees with
    /// the copy. If they ever diverge, the athlete is told "free" and charged, which is the
    /// worst bug this feature can have.
    var intendsFreeTrial: Bool { self == .yearly }

    /// Resolves a term from a product identifier, or nil for an unknown one.
    static func term(forProductID id: String) -> PremiumTerm? {
        allCases.first { $0.productID == id }
    }

    /// Every identifier to request from StoreKit.
    static var allProductIDs: [String] { allCases.map(\.productID) }
}

/// The paywall's arithmetic. Pure `Decimal` in, pure `Decimal` out — formatting belongs to
/// the product's own `priceFormatStyle`, so it lands in the athlete's currency and locale.
enum PremiumPricing {

    /// How much cheaper a year is than twelve months, as a whole percentage.
    ///
    /// **Rounded down, so the claim is never larger than the truth.** $29.99 against
    /// $4.99 × 12 saves 49.92 %, and half-up rounding advertised that as "SAVE 50%" — a
    /// number the athlete cannot reproduce from the two prices in front of them, on the one
    /// screen where every figure has to survive being checked. The difference between a
    /// rounding rule and an overstatement is the rounding mode.
    ///
    /// Returns nil when the comparison would be meaningless or unflattering — a missing
    /// price, or a yearly plan that is not actually cheaper. The badge is then simply not
    /// shown, rather than announcing "SAVE 0%".
    static func savingsPercent(monthlyPrice: Decimal, yearlyPrice: Decimal) -> Int? {
        guard monthlyPrice > 0, yearlyPrice > 0 else { return nil }
        let twelveMonths = monthlyPrice * 12
        guard yearlyPrice < twelveMonths else { return nil }
        let saved = (twelveMonths - yearlyPrice) / twelveMonths * 100
        let percent = NSDecimalNumber(decimal: rounding(saved, scale: 0, mode: .down)).intValue
        return percent > 0 ? percent : nil
    }

    /// A yearly price expressed per month, for the subordinate line under the real charge.
    /// Rounded to two places so it reads as money rather than as a division.
    ///
    /// Rounded to **nearest**, not down, and the asymmetry with `savingsPercent` is deliberate:
    /// each mode is chosen so the figure cannot flatter the plan. A saving rounded up overstates
    /// what the athlete gains; a monthly cost rounded down understates what they pay. $29.99 / 12
    /// is $2.4991…, whose nearest cent is $2.50 — quoting $2.49 would be the cheaper-looking lie.
    static func monthlyEquivalent(ofYearly yearlyPrice: Decimal) -> Decimal {
        guard yearlyPrice > 0 else { return 0 }
        return rounding(yearlyPrice / 12, scale: 2, mode: .plain)
    }

    /// `NSDecimalRound` at a fixed scale — Decimal has no rounding operator. The mode is always
    /// passed explicitly, because for money it is a decision rather than a default.
    private static func rounding(_ value: Decimal, scale: Int,
                                 mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode)
        return result
    }
}
