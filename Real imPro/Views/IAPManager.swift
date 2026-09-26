import StoreKit
import Combine

@MainActor
final class IAPManager: ObservableObject {
    static let shared = IAPManager()
    static let productID = "com.realimpro.master.lifetime"

    @Published var isPurchased = false
    @Published var product: Product?
    @Published var isPurchasing = false
    @Published var isRestoring = false
    @Published var errorMessage: String?
    @Published var isLoadingProduct = false

    private init() {
        #if DEBUG
        isPurchased = true
        #endif

        Task {
            await loadProduct()
            await checkCurrentEntitlements()
            await listenForTransactions()
        }
    }

    func loadProduct() async {
        isLoadingProduct = true; defer { isLoadingProduct = false }
        product = try? await Product.products(for: [Self.productID]).first
    }

    private func checkCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result, txn.productID == Self.productID {
                isPurchased = true; return
            }
        }
    }

    func purchase() async -> Bool {
        guard let product else {
            errorMessage = "无法连接 App Store，请检查网络后重试"
            return false
        }
        isPurchasing = true; defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let txn):
                    isPurchased = true; await txn.finish(); return true
                case .unverified:
                    errorMessage = "购买验证失败，请重试"; return false
                }
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "购买待处理，App Store 确认后将自动激活"
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "购买失败：\(error.localizedDescription)"
            return false
        }
    }

    func restore() async {
        isRestoring = true; defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await checkCurrentEntitlements()
            if isPurchased { errorMessage = nil }
            else { errorMessage = "未找到购买记录，请确认 Apple ID 是否正确" }
        } catch {
            errorMessage = "恢复失败：\(error.localizedDescription)"
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            switch result {
            case .verified(let txn):
                if txn.productID == Self.productID {
                    isPurchased = true; await txn.finish()
                }
            case .unverified:
                #if DEBUG
                dprint("⚠️ [IAP] 未验证的交易")
                #endif
            }
        }
    }
}
