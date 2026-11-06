# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Accounts: the card stack rolls like an endless deck. Drag over it to turn the cards one at a time
  in either direction, or tap a card behind to roll it to the front; tapping the front card opens
  it.

- "Back up now" writes the new portable backup file (`schemaVersion` 1), which the upcoming web app
  opens too: amounts and rates as exact text, and deleted records kept as deletions so they don't
  come back on another device. Files from earlier versions still restore, and a restore now
  replaces everything at once, so a damaged file leaves your data untouched.
- Deleting an account, card, movement or category now keeps a hidden record of the deletion, ready
  for syncing with other devices. "Delete all my data" still removes everything for good.

### Added

- Debts and loans, opened from home's new "Debts" card. A loan (bank or personal) has a lender,
  the amount borrowed in your main or second currency, the installment, how many and whether they
  fall monthly or weekly from the first due date. Its schedule shows each installment as paid or
  due, what's left and the next one; "Pay installment" records a confirmed expense from the account
  or card you pick ("Motorbike · 3/12", in the category you choose) and marks it paid. The next
  installment is reminded as many days ahead as card payments. Personal debts track money you lent
  ("they owe me") or borrowed ("I owe") with partial repayments and "Mark as settled"; like savings
  goals they never record movements or change balances. "Split" in a movement's menu divides an
  expense with other people (equal shares by default, editable), each of whom then owes you their
  part. The screen totals "You owe" and "Owed to you" one currency at a time. Backups move to
  `schemaVersion` 4 with `loans` and `personalDebts`; files from versions 1 to 3 still restore,
  with neither.
- Savings goals, like a pot or a vault but only on paper: give a goal a name, a target in your main
  or second currency, an optional target month, an icon and a color, then "Add money" or
  "Withdraw" as you set money aside. Nothing moves between your accounts and no movement is
  recorded. Each goal shows its progress and how much to set aside each month to arrive on time
  (rounded up to the cent), "Goal reached", or that the date passed. Open them from home's new
  "Savings goals" card, which previews the soonest goal and follows "hide balances". Backups move to
  `schemaVersion` 3 with `savingsGoals`; files from versions 1 and 2 still restore, with no goals.
- Monthly budgets per expense category: set one in the category editor (in your main currency;
  empty means no limit). Summary › Categories lists each budget for the selected month with how
  much is spent, left or over, and home warns about a category at 80% and again at 100% of its
  budget, with a notification once per category, threshold and month. A budget set in an earlier
  main currency is ignored, never converted. Backups carry the budget as an optional
  `monthlyBudget` on each category (still `schemaVersion` 2), and "Restore default categories"
  brings defaults back without one.
- Recurring movements and subscriptions: rent, salaries, transfers and subscriptions repeat every
  N weeks, months or years from their start date (the 31st stays the 31st in months that have
  one). Each time one comes due it's recorded on its date, as a draft to confirm or, with "Record
  automatically", already confirmed; after time away only the latest 12 are recorded, and a
  movement another device already recorded isn't repeated. The new Recurring screen (from home's
  "Upcoming" card or Settings › Organization) shows what subscriptions cost per month and per
  year, and each rule can be edited, paused, resumed or deleted (its pending drafts go with it).
  "Repeat" on a new movement's review turns it into a rule, a movement's menu opens the rule that
  recorded it, and subscriptions are reminded the morning before they renew. Backups move to
  `schemaVersion` 2 with the rules; version 1 files still restore.
- "Save as draft" on a movement's review: it's saved without counting toward balances until you
  confirm it. What the app called "Planned" is now "Drafts" everywhere (home, Transactions,
  reminders, widgets).
- Onboarding: the welcome screen has only "Start", and the next screen asks "Have you used Keepwell
  before?" with "Restore from iCloud", "Restore from a backup file (.json)" (accounts, cards and
  movements at once, straight to home) and "Start from scratch". The accounts step's CSV button
  reads "Import movements only (.csv)", since a CSV only adds movements to existing accounts.
- Settings › Currency: "Make NIO the main currency" swaps the main and second currencies and
  turns the rate around; net worth, summaries and new movements follow the new main currency, and
  past movements keep the rate they were logged with.
- Cards keep their product name ("Premia", "Platinum Walmart") and expiry month and year, from
  "Product and expiry" on a credit or debit card's screen. A card with a product name is shown as
  "Premia ··0633" (the credit card screen's title too); never the full number or CVV.
- Reminder on the first day of the month a card expires, listing the services charged to it
  again and again (the "Subscriptions" category, or the same charge in two months) so you can
  update them in time.
- Reminder on a credit card's cutoff morning: "statement closes today", since purchases from
  tomorrow go to next month's statement.
- Summary: the cash-flow chart shows your average spending per month as a dashed line, with
  "Average $X / month" in the legend.
- Settings › Payment methods lists each account with its card and bank transfer, with each
  card's expiry (in red when it expires this month or already did); a card opens its screen.
- Siri: "Log an expense from Cash in Keepwell" names the account in the phrase, credit cards can
  pay ("Premia ··0633"), and the answer shows a small card with the category, amount and account.

- Onboarding asks "What's your name?" right after the welcome (it can be skipped), and the
  name is the same one Settings › Security edits. Home then greets you by it ("Good morning,
  Steven"), the done screen says "All set, Steven", and your debit and credit cards print it
  in capitals, like a real plastic.
- Onboarding has a "Protect Keepwell" step before privacy: create the six-digit Keepwell passcode
  with the same screen as Settings, and keep Face ID or Touch ID on, or choose "Not now". A passcode
  made here keeps the lock on even with Face ID off, and a leftover passcode from an earlier install
  is cleared when none was made. The Face ID switch moved here from the privacy step, now titled
  "Your data stays yours".
- Settings › Categories is one editable list per kind: the shipped categories can now be renamed,
  given another icon and color, reordered ("Reorder") and deleted, like your own. A renamed default
  shows your name in every language; untouched ones keep translating. Deleted defaults stay deleted
  (also after restoring a backup), their movements move to "Other". "Other" and "Other income" can be renamed but not deleted. "Restore default
  categories" brings deleted defaults back and undoes edits to them, after a confirmation.
- Lock screen with a Keepwell passcode: a time-of-day greeting ("Good morning, Steven"), six
  passcode dots and a keypad whose corner key is Face ID or Touch ID, asked on its own when the
  screen appears. A wrong passcode shakes the dots with a haptic; after five, the keypad waits
  longer each time (30 seconds up to an hour). "Forgot your passcode?" gets in with the iPhone
  passcode and turns the Keepwell one off.
- Settings › Security: set up, change or turn off the Keepwell passcode (six digits, stored only on
  this iPhone as a salted hash in the Keychain), and the name the lock screen greets you with. The
  unlock choice "iPhone passcode" is now "Passcode only": the Keepwell passcode when there is one.
- Home greets you by time of day with today's date, and the hero's balance swipes like Revolut's:
  net worth first, then each account in its own currency (with its "≈" conversion) and what the
  cards owe, with page dots.
- Home: an eye button next to the balance hides every amount on the screen; the choice stays on
  this device.
- Home: the three latest movements, with "See all" opening Transactions.
- New movement flow in the style of a bank's "send to my own account": a "What are you recording?"
  sheet (expense, income, between my accounts, ATM withdrawal, card payment), a large amount with
  the app's own keypad, what the source has available and a note pill, a review card with what is
  left in each account and a pencil to change the amount, "Slide to save" to confirm (VoiceOver:
  double tap), and a ticket-style receipt with a reference.
- The receipt saves and shares as an image, as a bank's: "Save image" adds it to Photos (Keepwell
  only asks to add photos, never to read them, and points to Settings if access was turned off)
  and "Share" sends the picture, with the text receipt for apps that only take text. The image is
  the ticket on the brand gradient under the Keepwell wordmark, without the screen's buttons.
- Transfers, withdrawals and card payments start by choosing the accounts: the source as a card
  and the destination from the accounts that can receive it. When the destination keeps another
  currency, the amount, review and receipt say what arrives and at which rate.
- Categories: every category has its own icon, and there are new ones for pets, gifts, insurance,
  taxes, savings and donations, and for freelance, investments, rental and gifts received income.
- Create your own categories with a name, icon and color from "New category" when logging a
  movement (it starts from what you searched for), and rename, recolor or delete them in Settings ›
  Expense or Income categories. Deleting one moves its movements to "Other".
- Debit card screen: tap a debit card on Accounts to see it big with its account's name and
  balance, rename the account or change the card's color.
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
  card), the month's spending and savings, planned movements to confirm and every account's
  balance.
- Transactions: search, filters (all, expenses, income, transfers, planned), the month's totals and
  movements grouped by day; long-press to confirm a planned movement or delete one.
- Summary: three charts behind a switch, with a month stepper that moves them all. "Cash flow"
  pairs income and spending bars for six months with a green/red result bar per month and says it
  plainly ("You saved in November +$2,112", "You spent $44 more than came in") with the share kept
  and the six-month total. "Categories" is a ring of where the money went (top five, the rest
  grouped) with the list as its legend and an Expenses/Income switch. "Pace" compares this month's
  running spending with last month's by the same day. Every bar and slice reads out in VoiceOver.
- Credit card detail: current debt per currency, limit and available credit, cutoff and payment
  days and this cycle's movements; "Pay" opens a transfer to the card.
- Settings: exchange rate, payment reminders, unlock method, hide amounts, iCloud backup,
  CSV export and deleting all data.
- App lock with Face ID, Touch ID or the iPhone passcode, asked again after a chosen time away, and
  amounts hidden in the app switcher; the lock covers any flow left open. With "iPhone passcode"
  chosen, only the passcode is asked, never Face ID or Touch ID.
- Widgets: this month's spending, quick log in your usual categories, and net worth with your
  largest balances.
- Reminders: planned movements on their day (confirm or postpone from the notification) and card
  payments ahead of time.
- Siri and Shortcuts: "Log an expense in Keepwell" with amount, category and account.
- Import CSV from settings or onboarding; rows already recorded or for unknown accounts are skipped.
- Settings show when the data last reached iCloud, and "Back up now" / "Restore" save a complete
  backup file to iCloud Drive or Files and bring it back.
- The app is available in English and Spanish and follows the device language; English is the
  source language in code and every screen, error, accessibility label, date and the Face ID
  prompt have a Spanish translation in `Localizable.xcstrings` catalogs.
- Tabs without movements say so and offer to log one instead of an empty screen.
- Create transaction: amount and type with the app's keypad, category, payment method, review (real
  bank debit, note) and a saved summary with the rate used and the new balance.
- Add card: credit cards (plastic, debt in one or two currencies, billing cycle), debit cards linked
  to a bank account, new bank accounts and wallets.
- Accounts: credit cards stacked like Wallet, deposit accounts with their linked cards, and cash
  with "Reconcile" and "ATM withdrawal".
- Onboarding: splash, welcome with restore from iCloud, currencies ("One currency" or "Two
  currencies"; the main one starts as the iPhone's region currency, any ISO code can be searched,
  common ones are offered first and "Swap" exchanges main and second, inverting the manual rate),
  accounts (bank, credit card, cash), privacy and reminders, and a summary when done.
- Project setup: XcodeGen, Debug/Staging/Release configurations, widgets extension, SwiftFormat,
  SwiftLint (with layer-boundary rules), Lefthook, GitHub Actions and Dependabot.
- Packages: `Core` (`AppRouter`, `CurrencyFormatter`), `DesignSystem` (tokens, Inter typography,
  `KWSurfaceCard`), `Domain` (shared kernel), `Persistence` (SwiftData + CloudKit, versioned schema)
  and `Features`.
- `AppContainer` composition root with init-based dependency injection.
- Data stays on the iPhone with SwiftData and is backed up to the private iCloud database while
  "iCloud backup" is on (default); turning it off keeps data on the device only.

### Changed

- Accounts is one wallet: debit cards, credit cards and cash share a single Wallet-style stack,
  with chips to show all or one kind. Scrolling folds the cards into a deck at the top, and any
  card opens with a tap. "Reconcile" and "ATM withdrawal" are gone from Accounts; cash opens its
  movements.
- Keepwell tracks cards, it doesn't run them: additional cards (their screen, caps, allowed
  categories, cap reminders and setting), "Holder", "Plastics" and freezing a card are gone. Cards
  already saved as additional are skipped and older backups with them still restore; their
  purchases stay on the credit card. Cutoff and payment dates and their reminders stay.
- Card colors are the ones real cards come in: black, platinum, gold, blue, green and red, with
  platinum and gold drawn as metal and printed in dark ink. Cards in a color no longer offered keep
  it.
- "Card added" shows the new card straight, and the debt step no longer has a thumbnail beside its
  title.
- Logging a movement no longer asks whether it's planned or shared; it's saved as it happened.
- Onboarding's accounts: swipe an account left to remove it (a long swipe removes it at once),
  cash included. Cash starts in the main currency and its form lets you pick the currency; with
  two currencies you can keep cash in each, saved as "Cash USD" and "Cash NIO".

- A bank account is one card. Accounts shows each bank account as a single debit card with its
  balance (no stacks, no "Link another card", no empty "Add a debit card" slot), and tapping it
  opens one "Bank account" screen where the name and color apply to the account and its
  card. "Remove card" is now "Delete account", which says how many movements go with it and that
  transfers with other accounts go too.
- Adding a debit card creates its bank account (name, bank, last 4, currency and today's balance);
  "Other wallet" stays for cash. Onboarding gives a bank account its card even without the last 4.
- Existing data is brought to the rule at launch: accounts with several debit cards keep the most
  used one and its siblings' movements move to it; accounts without a card get one. No movement is
  deleted.
- Transactions' account filter is a flat list, one row per account shown with its card.
- "How did you pay?" shows each bank account once, as its card: the separate "Transfer or direct
  debit" / "Transfer or deposit" row is gone, since it moved the same balance. A movement last
  paid that way preselects the account's card.

- Expenses read as expenses: their amounts and arrow icon are coral red in Transactions, Home's
  recent movements, a card's cycle and the month's totals ("−$8.18" red, "+$817.79" green);
  Summary's "Went out" and Home's expense bar use the same color. The "−" sign stays.
- Transfers between your own accounts, ATM withdrawals and card payments are neutral: their amount
  is white and their icon grey instead of blue, because moving money between your accounts
  doesn't change what you have. Planned movements stay amber.
- Headline amounts stay white: Home's balance carousel shows what the cards owe in white like
  every other page, matching "Spent in …" and the net worth. Color marks single movements.

### Fixed

- Settings › Data: "Back up now" and "Restore" show with iCloud backup off too; they work with a
  file, not with iCloud.
- Settings: leaving the rate field without editing it no longer saves its rounded display over
  the exact rate; rates below one show six decimals.
- "Delete all my data" also deletes the iCloud copy itself, even with iCloud backup off; before,
  a copy uploaded earlier could stay in iCloud. If iCloud can't be reached, the iPhone is still
  emptied and trying again retries iCloud.
- Movements with an amount of zero or less, or a negative "charged by the bank", are refused
  wherever they come from (the app, ATM withdrawals and CSV imports skip those rows).

- Accounts: the add button opens "What do you want to add?" again. The cards' decoration reached
  past the plastic, so a credit card in the stack caught taps meant for the button and for the
  space above it.
- Widgets show your month, net worth and quick-log categories instead of always asking to open
  Keepwell. Development builds signed with a personal team kept the App Group out of the signature,
  so the widgets never saw what the app wrote; `APP_ENTITLEMENTS` now keeps it while dropping iCloud
  and Push. Widgets also refresh after any change to your movements, from any screen, and when you
  leave the app.
- Forms keep their main button ("Add", "Save", "Reconcile", "Continue") just above the keyboard
  instead of hidden behind the number pad, in onboarding accounts, new accounts and cards, debt,
  review, cash and card terms. Forms with several fields show previous / next
  and "Done" on top of the keyboard, return moves to the next field, and tapping outside or
  dragging the form hides the keyboard.
- Account and card forms: every editable value sits on a filled field, amounts show their currency
  symbol, card endings accept only four digits (also when pasted) and a new account starts typing
  in its first field. In onboarding's account form, amounts are tidied to "10,000.00" when you
  leave them, a half-typed ending or an amount that is not a number is explained under the form,
  and "Remove account" moved out of the footer, away from "Save".
- Cards look like real plastics everywhere: the bank, the masked number in the network's grouping
  ("•••• •••• •••• 1234", Amex 4-6-5), a gold chip with contacts, contactless, the network mark with
  "Debit" or "Credit" under it, your name and a glossy gradient. Credit and debit card screens open with the card big, its name
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
- Summary's category percentages ("100 %") no longer wrap onto two lines.
- The review step shows the suggested description as editable text instead of an empty field.
- The app icon shows the keepwell mark on the brand gradient, as on the brand board, drawn flat
  (Icon Composer layers without glass) so iOS 26 doesn't add a halo around the mark.
