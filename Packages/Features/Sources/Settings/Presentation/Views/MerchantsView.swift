import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Settings › Businesses: the merchants the person's movements name, each opening its editor.
/// Merchants are created from the movement editor, so there is no "New" here.
public struct MerchantsView: View {
    @Bindable private var viewModel: MerchantsViewModel
    private let onBack: () -> Void

    public init(viewModel: MerchantsViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWNavigationHeader(String(localized: "Businesses", bundle: #bundle), style: .large, onBack: onBack)
                if viewModel.merchants.isEmpty {
                    KWEmptyState(
                        icon: .globe,
                        title: String(localized: "No businesses yet", bundle: #bundle),
                        message: String(
                            localized: "Pick the business when you log a movement, and it shows up here to rename, merge or delete.",
                            bundle: #bundle,
                        ),
                    )
                    .padding(.top, KWSpacing.xl)
                } else {
                    KWGroupedCard {
                        ForEach(viewModel.merchants) { merchant in
                            Button { viewModel.edit(merchant) } label: { row(merchant) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if let error = viewModel.errorMessage {
                    Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .sheet(item: $viewModel.editor) { editor in
            MerchantEditorView(
                viewModel: editor,
                onDone: { Task { await viewModel.editorFinished() } },
                onClose: { viewModel.editor = nil },
            )
        }
    }

    private func row(_ merchant: Merchant) -> some View {
        HStack(spacing: KWSpacing.sm) {
            if let logo = viewModel.logo(of: merchant) {
                BrandMark(logo, tint: KWColor.Text.secondary, diameter: 38)
            } else {
                Text(verbatim: String(merchant.name.prefix(1)).uppercased())
                    .font(.kw(15, weight: 700))
                    .foregroundStyle(KWColor.Text.secondary)
                    .frame(width: 38, height: 38)
                    .background(KWColor.Surface.surface2, in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: merchant.name).font(KWTextStyle.body.font).lineLimit(1)
                Text(viewModel.detail(of: merchant))
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: KWSpacing.xs)
            KWIconView(.chevronRight, size: 16).foregroundStyle(KWColor.Text.muted)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Rename, web address (for the logo), default category, platform, merge and delete.
struct MerchantEditorView: View {
    @Bindable var viewModel: MerchantEditorViewModel
    let onDone: () -> Void
    let onClose: () -> Void
    @State private var isConfirmingDelete = false
    @State private var mergeTarget: Merchant?

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                suggestionSection
                if !viewModel.mergeTargets.isEmpty {
                    mergeSection
                }
                Section {
                    Button(role: .destructive) { isConfirmingDelete = true } label: {
                        Text("Delete business", bundle: #bundle)
                    }
                }
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(KWColor.State.negative)
                }
            }
            .navigationTitle(viewModel.merchant.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog(
                String(localized: "Delete this business?", bundle: #bundle),
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible,
            ) {
                Button(role: .destructive) { finish(viewModel.delete) } label: {
                    Text("Delete business", bundle: #bundle)
                }
            } message: {
                Text("Its movements keep everything else and no longer name a business.", bundle: #bundle)
            }
            .confirmationDialog(
                String(localized: "Merge into \(mergeTarget?.name ?? "")?", bundle: #bundle),
                isPresented: isMerging,
                titleVisibility: .visible,
            ) {
                Button { merge() } label: { Text("Merge", bundle: #bundle) }
            }
        }
    }

    private var isMerging: Binding<Bool> {
        Binding(get: { mergeTarget != nil }, set: { isShown in
            if !isShown {
                mergeTarget = nil
            }
        })
    }

    private func merge() {
        guard let target = mergeTarget else { return }
        finish { await viewModel.merge(into: target) }
    }

    /// Runs an action that closes the editor once it is stored.
    private func finish(_ action: @escaping () async -> Bool) {
        Task {
            if await action() {
                onDone()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: onClose) { Text("Cancel", bundle: #bundle) }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button { finish(viewModel.save) } label: { Text("Save", bundle: #bundle) }
                .disabled(!viewModel.canSave)
        }
    }

    private var nameSection: some View {
        Section {
            TextField(String(localized: "Name", bundle: #bundle), text: $viewModel.name)
            TextField(String(localized: "Web address (for the logo)", bundle: #bundle), text: $viewModel.domain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
    }

    private var suggestionSection: some View {
        Section {
            Picker(String(localized: "Default category", bundle: #bundle), selection: $viewModel.defaultCategoryID) {
                Text("None", bundle: #bundle).tag(String?.none)
                ForEach(viewModel.categories) { category in
                    Text(CategoryDisplay.name(of: category)).tag(Optional(category.id))
                }
            }
            Toggle(String(localized: "Platform", bundle: #bundle), isOn: $viewModel.isPlatform)
        } footer: {
            Text(
                """
                A new movement with this business takes its category when no rule picks one. \
                Platforms (delivery apps, app stores) come first in “Via”.
                """,
                bundle: #bundle,
            )
        }
    }

    private var mergeSection: some View {
        Section {
            Menu {
                ForEach(viewModel.mergeTargets) { target in
                    Button(target.name) { mergeTarget = target }
                }
            } label: {
                Text("Merge into…", bundle: #bundle)
            }
        } footer: {
            Text("Its movements and rules move to the other business, and this one is deleted.", bundle: #bundle)
        }
    }
}
