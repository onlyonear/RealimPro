import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var iapManager: IAPManager
    @Environment(\.dismiss) var dismiss
    var onUnlock: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 16)

            Text("Unlock Master Algorithms")
                .font(.largeTitle.weight(.bold))

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(text: "Advanced jazz grammar engine")
                FeatureRow(text: "Lifetime access, one-time purchase")
            }
            .padding(.horizontal, 32)

            Spacer()

            if let product = iapManager.product {
                Button {
                    Task {
                        if await iapManager.purchase() { onUnlock?() }
                    }
                } label: {
                    HStack {
                        if iapManager.isPurchasing {
                            ProgressView()
                        }
                        Text("\(product.displayPrice) — Lifetime")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(iapManager.isPurchasing)
                .padding(.horizontal, 32)
            } else if iapManager.isLoadingProduct {
                ProgressView("Connecting to App Store...")
            } else {
                VStack(spacing: 8) {
                    Text("Cannot connect to App Store")
                        .foregroundColor(.secondary)
                    Button("Retry") { Task { await iapManager.loadProduct() } }
                }
            }

            Button {
                Task { await iapManager.restore() }
            } label: {
                HStack {
                    if iapManager.isRestoring {
                        ProgressView()
                    }
                    Text("Restore Purchase")
                }
            }
            .disabled(iapManager.isRestoring)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium])
        .onAppear { iapManager.errorMessage = nil }
        .onChange(of: iapManager.isPurchased) { purchased in
            if purchased { onUnlock?() }
        }
        .onChange(of: iapManager.errorMessage) { msg in
            if msg != nil, !iapManager.isPurchased, !iapManager.isRestoring { }
        }
        .alert("Notice", isPresented: Binding<Bool>(
            get: { iapManager.errorMessage != nil && !iapManager.isPurchased },
            set: { if !$0 { iapManager.errorMessage = nil } }
        )) {
            Button("OK") { iapManager.errorMessage = nil }
        } message: {
            Text(iapManager.errorMessage ?? "")
        }
    }
}

private struct FeatureRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.accentColor)
            Text(text)
                .font(.body)
        }
    }
}
