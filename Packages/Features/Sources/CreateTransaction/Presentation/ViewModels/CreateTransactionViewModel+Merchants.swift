import CreateTransactionDomain
import Domain
import Foundation
import SharedPresentation

/// "Business" and "Via" (keepwell-web's `movement-editor/merchant-state.ts`). A new movement's
/// description (or a matching rule) suggests the business until the person picks or clears it; the
/// business may bring its default category when nobody chose one. A merchant picked from the brand
/// table, Brandfetch or typed by hand is created only when the movement is saved.
extension CreateTransactionViewModel {
    /// What the two fields hold, and whether the person chose the business.
    struct MerchantFields {
        var business: MerchantChoice?
        var via: MerchantChoice?
        /// The person picked or cleared the business; an edit starts so.
        var touched = false
        /// The category the business suggested, so another suggestion (or none) can take it back.
        var suggestedCategory: String?
        var picker: MerchantPickerViewModel?
    }

    /// The open "Business" or "Via" picker.
    public var merchantPicker: MerchantPickerViewModel? {
        get { merchantFields.picker }
        set { merchantFields.picker = newValue }
    }

    /// The description or note changed: rules and the suggested business follow it.
    func textChanged() {
        applyRules()
        suggestBusiness()
    }

    /// Shown for expenses and income once the context knows the person's merchants.
    public var showsMerchantFields: Bool {
        context?.merchants != nil && !type.movesBetweenAccounts
    }

    public var merchants: [Merchant] {
        context?.merchants ?? []
    }

    public var businessChoice: MerchantChoice? {
        merchantFields.business
    }

    public var viaChoice: MerchantChoice? {
        merchantFields.via
    }

    public var businessName: String? {
        merchantFields.business?.name(in: merchants)
    }

    public var viaName: String? {
        merchantFields.via?.name(in: merchants)
    }

    public var businessLogo: LogoSubject? {
        merchantFields.business?.logo(in: merchants)
    }

    /// The fields an edit opens with: the movement's own links, chosen as far as suggestions go.
    func loadMerchantFields(of transaction: Transaction) {
        merchantFields = MerchantFields(
            business: transaction.merchantID.map(MerchantChoice.merchant),
            via: transaction.viaMerchantID.map(MerchantChoice.merchant),
            touched: true,
        )
    }

    func resetMerchantFields() {
        merchantFields = MerchantFields()
    }

    // MARK: Pickers

    public func openBusinessPicker() {
        merchantPicker = MerchantPickerViewModel(
            role: .business,
            merchants: merchants,
            current: merchantFields.business,
            search: brandSearch,
        ) { [weak self] choice in
            self?.chooseBusiness(choice)
        }
    }

    public func openViaPicker() {
        merchantPicker = MerchantPickerViewModel(
            role: .via,
            merchants: merchants,
            current: merchantFields.via,
            excluding: merchantFields.business?.merchantID,
            search: brandSearch,
        ) { [weak self] choice in
            self?.chooseVia(choice)
        }
    }

    /// The person chose (or cleared) the business: no suggestion replaces it from now on.
    public func chooseBusiness(_ choice: MerchantChoice?) {
        merchantPicker = nil
        withBusiness(choice, mayChoose: !categoryPickedByPerson && appliedRule == nil, touched: true)
        if let via = merchantFields.via, via == choice {
            merchantFields.via = nil
        }
    }

    public func chooseVia(_ choice: MerchantChoice?) {
        merchantPicker = nil
        merchantFields.via = choice == merchantFields.business ? nil : choice
    }

    // MARK: Suggestions

    /// The business the text suggests while the person hasn't chosen one: a matching rule's
    /// merchant first, else the person's merchant (or the table's brand) the description names. It
    /// brings its category when nobody chose one (no pick, no rule).
    func suggestBusiness() {
        guard case .create = mode, let context, showsMerchantFields, !merchantFields.touched else { return }
        // The suggested description is the category's own name, not something the person typed.
        let typed = description == prefilledDescription || description == descriptionPlaceholder ? "" : description
        let rule = CategorizationRules.firstMatch(in: context.rules, kind: kind, description: typed, note: note)
        let choice: MerchantChoice? = if let id = rule?.merchantID, merchants.contains(where: { $0.id == id }) {
            .merchant(id)
        } else {
            MerchantLogos.suggestedMerchant(for: typed, merchants: merchants)
        }
        guard choice != merchantFields.business else { return }
        withBusiness(choice, mayChoose: !categoryPickedByPerson && rule == nil, touched: false)
    }

    /// The business changes to `choice`, and the category with it when it may: the business's
    /// default when the person hasn't picked a category, back to none when the category was the
    /// previous business's suggestion, otherwise as it was.
    private func withBusiness(_ choice: MerchantChoice?, mayChoose: Bool, touched: Bool) {
        let ownedBySuggestion = merchantFields.suggestedCategory != nil && categoryID == merchantFields.suggestedCategory
        merchantFields.business = choice
        merchantFields.touched = touched
        guard mayChoose, !isEditing, let context else {
            merchantFields.suggestedCategory = ownedBySuggestion ? merchantFields.suggestedCategory : nil
            return
        }
        let suggested = Merchants.category(of: context.merchant(choice?.merchantID), kind: kind, categories: context.categories)
        if let suggested, categoryID == nil || ownedBySuggestion {
            categoryID = suggested
            merchantFields.suggestedCategory = suggested
        } else {
            if ownedBySuggestion {
                categoryID = nil
            }
            merchantFields.suggestedCategory = nil
        }
    }

    // MARK: Saving

    /// The links a movement saves: the business and the platform, `none` for an empty field so
    /// clearing one unlinks it (`unlinked`). A merchant picked from the brand table, Brandfetch or typed by hand
    /// travels as `new`, and saving creates it in the same write as the movement. A transfer names
    /// neither; without merchants loaded the movement's links are kept as they are.
    var merchantLinks: (merchant: MerchantLink, via: MerchantLink) {
        guard context?.merchants != nil else { return (.keep, .keep) }
        guard !type.movesBetweenAccounts else { return (.unlinked, .unlinked) }
        let via = merchantFields.via == merchantFields.business ? nil : merchantFields.via
        return (Self.link(merchantFields.business), Self.link(via))
    }

    private static func link(_ choice: MerchantChoice?) -> MerchantLink {
        switch choice {
        case nil: .unlinked
        case let .merchant(id): .merchant(id)
        case let .new(draft): .new(draft)
        }
    }
}
