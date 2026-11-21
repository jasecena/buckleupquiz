import Foundation
import Observation
import StoreKit

/// App Store purchases with StoreKit 2 (ADR-0022): the BuckleUp Basic subscription and
/// 50-question packs. Purchases are only offered behind the parental gate.
@MainActor
@Observable
final class StoreService {
    static let basicMonthly = "com.jcena.buckleupquiz.basic.monthly"
    static let questionPack = "com.jcena.buckleupquiz.questions50"

    private(set) var products: [String: Product] = [:]
    private(set) var isSubscribed = false
    private(set) var isBusy = false
    private(set) var message: String?

    /// A pack was bought (the transaction id, so it's credited exactly once).
    @ObservationIgnored var onPackBought: ((UInt64) -> Void)?
    /// The subscription started, renewed, lapsed or was refunded.
    @ObservationIgnored var onSubscriptionChanged: ((Bool) -> Void)?
    @ObservationIgnored private var updates: Task<Void, Never>?

    var basic: Product? { products[Self.basicMonthly] }
    var pack: Product? { products[Self.questionPack] }

    /// Listens for purchases made elsewhere (renewals, Ask to Buy, other devices), then loads
    /// the products and the current subscription.
    func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates { await self?.handle(result) }
            }
        }
        await loadProducts()
        await refreshSubscription()
        for await result in Transaction.unfinished { await handle(result) }
    }

    func loadProducts() async {
        guard let loaded = try? await Product.products(for: [Self.basicMonthly, Self.questionPack]) else { return }
        products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
    }

    func refreshSubscription() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.basicMonthly,
               transaction.revocationDate == nil {
                active = true
            }
        }
        if active != isSubscribed {
            isSubscribed = active
            onSubscriptionChanged?(active)
        }
    }

    /// Buys a product. Returns true when it went through.
    func buy(_ productID: String) async -> Bool {
        message = nil
        if products[productID] == nil { await loadProducts() }
        guard let product = products[productID] else {
            message = "Purchases aren't available right now. Please try again later."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await handle(result)
                return true
            case .pending:
                message = "Waiting for approval (Ask to Buy)."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func restore() async {
        isBusy = true
        defer { isBusy = false }
        try? await AppStore.sync()
        await refreshSubscription()
        message = isSubscribed ? "BuckleUp Basic is active." : "No active subscription found."
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == Self.questionPack, transaction.revocationDate == nil {
            onPackBought?(transaction.id)
        }
        await transaction.finish()
        if transaction.productID == Self.basicMonthly { await refreshSubscription() }
    }
}
