import DesignSystem
import Domain
import SwiftUI

/// Step 0 · Language. Shown once, before the welcome screen.
public struct LanguageView: View {
    @Bindable private var viewModel: OnboardingViewModel

    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        KWScreen(top: 64, bottom: 40, horizontal: 20) {
            KWGlowBackground(.brand)
        } content: {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWAppIconTile()
                    .padding(.bottom, KWSpacing.xs)
                OnboardingHeading(
                    title: String(localized: "Choose your language", bundle: #bundle),
                    message: String(localized: "You can change it later in Settings.", bundle: #bundle),
                )
                VStack(spacing: KWSpacing.xs) {
                    ForEach(viewModel.languages, id: \.self) { language in
                        option(language)
                    }
                }
                .padding(.top, KWSpacing.xs)
                if let reopen = viewModel.languageNeedingReopen {
                    reopenNote(reopen)
                }
                Spacer(minLength: KWSpacing.md)
                if viewModel.languageNeedingReopen == nil {
                    Button { viewModel.confirmLanguage() } label: {
                        Text("Continue", bundle: #bundle)
                    }
                    .buttonStyle(.kw())
                }
            }
        }
        .animation(.snappy, value: viewModel.languageNeedingReopen)
    }

    private func option(_ language: AppLanguage) -> some View {
        let isSelected = viewModel.selectedLanguage == language
        let shape = RoundedRectangle(cornerRadius: KWSpacing.md, style: .continuous)
        return Button {
            viewModel.selectedLanguage = language
        } label: {
            HStack {
                Text(verbatim: language.nativeName)
                    .font(.kw(17, weight: 700))
                Spacer()
                if isSelected {
                    KWIconView(.check, size: 20)
                }
            }
            .foregroundStyle(isSelected ? Color.black : KWColor.Text.primary)
            .padding(.horizontal, KWSpacing.md)
            .frame(height: 58)
            .background(isSelected ? Color.white : KWColor.Surface.surface, in: shape)
            .overlay { shape.strokeBorder(isSelected ? Color.white : KWColor.Surface.border) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.languageNeedingReopen != nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The chosen language's translations, so the note is readable by whoever picked it even
    /// though the screen is still in the other language.
    private static func bundle(for language: AppLanguage) -> Bundle {
        #bundle.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? #bundle
    }

    /// iOS applies an app's language when it opens, so the person reopens Keepwell to continue.
    private func reopenNote(_ language: AppLanguage) -> some View {
        let name = language.nativeName
        return HStack(alignment: .top, spacing: KWSpacing.sm) {
            KWIconView(.phone, size: 22)
                .foregroundStyle(KWColor.Brand.link)
            Text("Close Keepwell and open it again to continue in \(name).", bundle: Self.bundle(for: language))
                .font(KWTextStyle.body.font)
                .foregroundStyle(KWColor.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }
}
