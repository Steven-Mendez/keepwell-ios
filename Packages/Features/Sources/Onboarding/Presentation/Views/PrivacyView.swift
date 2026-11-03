import DesignSystem
import SwiftUI

/// Step 4 · Privacidad y avisos.
public struct PrivacyView: View {
    @Bindable private var viewModel: OnboardingViewModel
    private let onBack: () -> Void

    public init(viewModel: OnboardingViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        KWScreen(bottom: 40) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.back, progress: (3, 3), action: onBack)
                OnboardingHeading(
                    title: "Protege tus datos",
                    message: "Sin cuenta y sin nuestros servidores. Tus datos viven en tu iPhone y, si quieres, en tu iCloud.",
                )
                KWGroupedCard {
                    toggle("Face ID o Touch ID", "El que tenga tu iPhone; si falla, tu código", isOn: $viewModel.locksWithBiometrics)
                    toggle("Respaldo en iCloud", "Recupera todo si cambias de iPhone", isOn: $viewModel.backsUpToICloud)
                    toggle("Ocultar montos al salir", "En el selector de apps", isOn: $viewModel.hidesAmountsInAppSwitcher)
                }
                notificationsCard
                Spacer(minLength: 0)
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                        .frame(maxWidth: .infinity)
                }
                VStack(spacing: KWSpacing.md) {
                    Button("Permitir avisos") { Task { await viewModel.allowNotifications() } }
                        .buttonStyle(.kw())
                    Button("Ahora no") { Task { await viewModel.skipNotifications() } }
                        .buttonStyle(.kw(.plain, size: .text))
                }
                .disabled(viewModel.isSaving)
            }
        }
    }

    private func toggle(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            KWTitleSubtitle(title, subtitle: subtitle)
        }
        .toggleStyle(.kw)
        .padding(.vertical, 14)
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            Text("Avisos útiles, sin spam").font(.kw(15, weight: 700))
            VStack(alignment: .leading, spacing: 10) {
                bullet(KWColor.State.pending, "Gastos previstos que vencen hoy")
                bullet(KWColor.Brand.accent, "Corte y pago de tus tarjetas")
                bullet(KWColor.State.extra, "Topes de tarjetas adicionales")
            }
            .font(KWTextStyle.label.font.weight(.regular))
            .foregroundStyle(KWColor.Text.secondary)
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface))
    }

    private func bullet(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}
