# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Lock screen with a Keepwell passcode: a time-of-day greeting ("Good morning, Steven"), six
  passcode dots and a keypad whose corner key is Face ID or Touch ID, asked on its own when the
  screen appears. A wrong passcode shakes the dots with a haptic; after five, the keypad waits
  longer each time (30 seconds up to an hour). "Forgot your passcode?" gets in with the iPhone
  passcode and turns the Keepwell one off.
- Settings › Security: set up, change or turn off the Keepwell passcode (six digits, stored only on
  this iPhone as a salted hash in the Keychain), and the name the lock screen greets you with. The
  unlock choice "iPhone passcode" is now "Passcode only": the Keepwell passcode when there is one.

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

- Builds signed without iCloud (free developer accounts) open with on-device storage instead of
  closing at launch.
- Siri's prompts and messages appear in Spanish on Spanish iPhones.
- The add and edit account forms in onboarding no longer draw their buttons over the title.
- Launch goes straight from the brand blue to the splash, with no black flash in between.
- Additional cards on a two-currency credit card are capped in the local currency.
- The review step shows the suggested description as editable text instead of an empty field.
- The app icon shows the keepwell mark on the brand gradient, as on the brand board, drawn flat
  (Icon Composer layers without glass) so iOS 26 doesn't add a halo around the mark.
