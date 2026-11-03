# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Debit card screen: tap a debit card on Accounts to see it big with its account's name and
  balance, rename the account, change the card's color, freeze it, link another card or remove it.
- Credit cards can be renamed and recolored from their screen, under a new "Manage card" list.
- Transactions per account and card: an "All accounts" chip on Transactions opens a picker of
  accounts and their cards; the month's totals and search follow the choice, and the chip's ✕
  clears it.
- Debit card screen: the account's latest movements with "See all"; credit card screen: "See all"
  on "This cycle" opens the card's whole history. Both open the list already filtered.
- Cash: tap the banknote or "See movements" to see the cash account's movements and balance.
- Account and card screens show the balance big, with an eye to hide it; the choice is
  remembered.

- Settings › Language shows the app's language and opens the iPhone's Settings to pick another
  one only for Keepwell; the app follows the iPhone's language otherwise.
- The settings button is a gear.
- Home: net worth with its second-currency equivalent, quick actions (expense, income, move, pay
  card), the month's spending and savings, planned movements to confirm, additional cards against
  their cap and every account's balance.
- Transactions: search, filters (all, expenses, income, transfers, planned), the month's totals and
  movements grouped by day; long-press to confirm a planned movement or delete one.
- Summary: six months of spending or income with the average, what came in and went out, savings
  rate and spending by category.
- Credit card detail: current debt per currency, limit and available credit, cutoff and payment
  days, plastics and this cycle's movements; "Pay" opens a transfer to the card.
- Additional cards: add one, freeze it, set a cap per cycle, choose where it can be used, alerts
  and the category its purchases default to.
- Settings: exchange rate, payment and cap reminders, unlock method, hide amounts, iCloud backup,
  CSV export and deleting all data.
- App lock with Face ID, Touch ID or the iPhone passcode, asked again after a chosen time away, and
  amounts hidden in the app switcher; the lock covers any flow left open. With "iPhone passcode"
  chosen, only the passcode is asked, never Face ID or Touch ID.
- Widgets: this month's spending, quick log in your usual categories, and net worth with your
  largest balances.
- Reminders: planned movements on their day (confirm or postpone from the notification), card
  payments ahead of time and additional cards reaching their cap.
- Siri and Shortcuts: "Log an expense in Keepwell" with amount, category and account.
- Import CSV from settings or onboarding; rows already recorded or for unknown accounts are skipped.
- Freeze a credit card's main plastic so it can't be chosen to pay.
- Settings show when the data last reached iCloud, and "Back up now" / "Restore" save a complete
  backup file to iCloud Drive or Files and bring it back.
- The app is available in English and Spanish and follows the device language; English is the
  source language in code and every screen, error, accessibility label, date and the Face ID
  prompt have a Spanish translation in `Localizable.xcstrings` catalogs.
- Tabs without movements say so and offer to log one instead of an empty screen.
- Create transaction: amount and type with the app's keypad, category, payment method, review (real
  bank debit, planned, shared, note) and a saved summary with the rate used and the new balance.
- Add card: credit cards (plastic, debt in one or two currencies, billing cycle), debit cards linked
  to a bank account, new bank accounts and wallets.
- Accounts: credit cards stacked like Wallet, deposit accounts with their linked cards, and cash
  with "Reconcile" and "ATM withdrawal".
- Onboarding: splash, welcome with restore from iCloud, currencies with a manual rate (default 1),
  accounts (bank, credit card, cash), privacy and reminders, and a summary when done.
- Project setup: XcodeGen, Debug/Staging/Release configurations, widgets extension, SwiftFormat,
  SwiftLint (with layer-boundary rules), Lefthook, GitHub Actions and Dependabot.
- Packages: `Core` (`AppRouter`, `CurrencyFormatter`), `DesignSystem` (tokens, Inter typography,
  `KWSurfaceCard`), `Domain` (shared kernel), `Persistence` (SwiftData + CloudKit, versioned schema)
  and `Features`.
- `AppContainer` composition root with init-based dependency injection.
- Data stays on the iPhone with SwiftData and is backed up to the private iCloud database while
  "iCloud backup" is on (default); turning it off keeps data on the device only.

### Fixed

- Cards look like real plastics everywhere: the bank, the masked number in the network's grouping
  ("•••• •••• •••• 1234", Amex 4-6-5), a gold chip with contacts, contactless, the network mark with
  "Debit" or "Credit" under it, the holder's name on additional cards and a glossy gradient. Frozen
  cards turn grey with a snowflake. Credit and debit card screens open with the card big, its name
  and round quick actions, as banks show "my card".
- Accounts shows every bank account through its debit cards, stacked like the credit cards, and
  cash as a banknote. The "Transfers" row is gone from the accounts list; a bank account without a
  card shows an empty card slot to add one.
- "How did you pay?" explains paying from a bank account without a card: the bare "Transfer" row is
  now "Bank transfer · Charged directly to the account" with a transfer icon, after the account's
  cards. Accounts beyond the two most used are grouped as bank accounts, cash and credit cards
  instead of "Other"; credit cards show their bank instead of "Credit · holder" and cash shows its
  name and what's available.
- Movements name the card or account that paid them ("Visa •••• 3141", "LAFISE · Bank transfer")
  instead of "Holder" or "Transfers LAFISE".
- Builds signed without iCloud (free developer accounts) open with on-device storage instead of
  closing at launch.
- Siri's prompts and messages appear in Spanish on Spanish iPhones.
- The add and edit account forms in onboarding no longer draw their buttons over the title.
- Launch goes straight from the brand blue to the splash, with no black flash in between.
- Additional cards on a two-currency credit card are capped in the local currency.
- The review step shows the suggested description as editable text instead of an empty field.
- The app icon shows the keepwell mark on the brand gradient, as on the brand board, drawn flat
  (Icon Composer layers without glass) so iOS 26 doesn't add a halo around the mark.
