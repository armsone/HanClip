import Combine
import StoreKit

@MainActor
final class CopyrightPurchaseManager: ObservableObject {
    static let shared = CopyrightPurchaseManager()
    static let productID = "com.intosharp.hanclip.copyright"

    @Published private(set) var product: Product?
    @Published private(set) var isPurchased = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isLoading = false
    @Published var message: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = observeTransactionUpdates()
        Task {
            await refresh()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        await loadProduct(showEmptyProductMessage: false)
        await updateEntitlement()
    }

    func purchase() async {
        guard !isPurchasing else { return }
        if product == nil {
            await loadProduct(showEmptyProductMessage: true)
        }
        guard let product else {
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let result):
                let transaction = try verified(result)
                await transaction.finish()
                await updateEntitlement()
            case .pending:
                message = "구매 승인을 기다리고 있습니다. 승인이 끝나면 자동으로 반영됩니다."
            case .userCancelled:
                message = cancelledPurchaseMessage
            @unknown default:
                message = "구매 결과를 확인할 수 없습니다. 잠시 후 다시 시도해 주세요."
            }
        } catch {
            message = purchaseErrorMessage(for: error)
        }
    }

    func restore() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await updateEntitlement()
            message = isPurchased
                ? "구매 내역을 복원했습니다."
                : "복원할 구매 내역이 없습니다."
        } catch {
            message = "구매 복원에 실패했습니다. \(error.localizedDescription)"
        }
    }

    private func loadProduct(showEmptyProductMessage: Bool) async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if product == nil, showEmptyProductMessage {
                message = emptyProductMessage
            }
        } catch {
            product = nil
            message = "구매 상품을 불러오지 못했습니다. \(error.localizedDescription)"
        }
    }

    private var emptyProductMessage: String {
#if DEBUG
        """
        상품 정보가 등록되지 않은 실행 환경입니다.

        로컬 테스트: Xcode의 HanClip Scheme > Run > Options에서 HanClip.storekit을 선택한 뒤 Xcode에서 다시 실행해 주세요.

        Sandbox/실기기: App Store Connect에서 상품의 가격, 현지화, 판매 지역을 모두 저장했는지 확인해 주세요.
        """
#else
        "구매 상품을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요."
#endif
    }

    private var cancelledPurchaseMessage: String {
#if DEBUG
        """
        구매가 완료되지 않았습니다.

        Sandbox 테스트라면 일반 Apple 계정이 아니라 App Store Connect에서 만든 Sandbox 테스트 계정으로 기기의 설정 > 개발자 > Sandbox Apple 계정에 로그인했는지 확인해 주세요.

        로컬 StoreKit 테스트에서는 실제 Apple 계정 로그인이 필요하지 않습니다. 로그인 창이 나타났다면 HanClip.storekit이 활성화되지 않은 실행입니다.
        """
#else
        "구매가 완료되지 않았습니다. 결제 정보를 확인한 뒤 다시 시도해 주세요."
#endif
    }

    private func updateEntitlement() async {
        var hasEntitlement = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil else {
                continue
            }
            hasEntitlement = true
            break
        }

        isPurchased = hasEntitlement
        if !hasEntitlement {
            UserDefaults.standard.set(
                false,
                forKey: WatermarkSettings.logoEnabledStorageKey
            )
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.updateEntitlement()
            }
        }
    }

    private func verified<T>(
        _ result: VerificationResult<T>
    ) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw PurchaseError.failedVerification
        }
    }

    private func purchaseErrorMessage(for error: Error) -> String {
        return "구매에 실패했습니다. \(error.localizedDescription)"
    }
}

private enum PurchaseError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "구매 정보를 확인할 수 없습니다."
    }
}
