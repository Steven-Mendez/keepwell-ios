import DesignSystem
import Domain
import SwiftUI

/// Step 2 · What to call the person. One field and a way past it: the name only makes the
/// greeting and the cards feel like theirs, so nothing breaks without it.
public struct NameView: View {
    @Bindable private var viewModel: OnboardingViewModel
    private let onBack: () -> Void
    @FocusState private var isFocused: Bool

    public init(viewModel: OnboardingViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        KWFormScreen(bottom: 40) {
            VStack(alignment: .leading, spacing: 18) {
                KWFlowHeader(.back, progress: (5, 1), action: onBack)
                OnboardingHeading(
                    title: String(localized: "What should we call you?", bundle: #bundle),
                    message: String(
                        localized: "We'll greet you by name and print it on your cards. It stays on this iPhone.",
                        bundle: #bundle,
                    ),
                )
                TextField(String(localized: "Your first name", bundle: #bundle), text: $viewModel.nameText)
                    .font(.kw(22, weight: 700, relativeTo: .title3))
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($isFocused)
                    .onSubmit(next)
                    .padding(.horizontal, KWSpacing.md)
                    .frame(height: 60)
                    .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface))
                    .accessibilityLabel(Text("Your name", bundle: #bundle))
                    .onChange(of: viewModel.nameText) { _, text in
                        if text.count > PreferredName.maxLength {
                            viewModel.nameText = String(text.prefix(PreferredName.maxLength))
                        }
                    }
            }
        } footer: {
            VStack(spacing: KWSpacing.md) {
                Button(action: next) { Text("Continue", bundle: #bundle) }
                    .buttonStyle(.kw())
                    .disabled(viewModel.preferredName == nil)
                Button {
                    KWKeyboard.dismiss()
                    viewModel.skipName()
                } label: {
                    Text("Skip", bundle: #bundle)
                }
                .buttonStyle(.kw(.plain, size: .text))
            }
        }
        .onAppear { isFocused = true }
    }

    private func next() {
        guard viewModel.preferredName != nil else { return }
        KWKeyboard.dismiss()
        viewModel.continueFromName()
    }
}
