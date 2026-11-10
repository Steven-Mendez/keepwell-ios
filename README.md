# Keepwell

Personal finance iOS app for two currencies. Data lives on device with SwiftData. An optional
Keepwell account (Sign in with Apple or a passkey, invite-only) syncs it with Keepwell on the web
through the Keepwell API; without one, everything stays on the device. CSV export and import are
the manual way to keep or move a copy.

Sync notes (`SyncEngine`): an id the account already deleted can't be revived by "Keep this
iPhone's data". Switching accounts on one device treats unsent changes as this device's data: the
person is asked which side to keep if the new account has data, and this device's data uploads if
it is empty. "Delete all my data" while signed in signs out first, then erases this iPhone only.

> Status: **in development**. Screens are built feature by feature from `design/keepwell-design`.

## Requirements

| Tool                         | Version                                               |
| ---------------------------- | ----------------------------------------------------- |
| Xcode                        | 27.1 (Swift 6.4, language mode 6, strict concurrency) |
| iOS deployment target        | 26.0                                                  |
| [mise](https://mise.jdx.dev) | any recent version (`brew install mise`)              |

mise installs the versions pinned in [`.mise.toml`](.mise.toml): XcodeGen 2.46.0, SwiftLint 0.65.1,
SwiftFormat 0.63.1 and Lefthook 2.2.2.

Tip: add `eval "$(mise activate zsh)"` to your `~/.zshrc` so the pinned tools take precedence over
any Homebrew copies (git hooks resolve `lefthook` from your `PATH`).

## Getting started

```sh
brew install mise      # once
make bootstrap         # install tools, generate Keepwell.xcodeproj, install git hooks
make run               # build and launch on the simulator
make open              # open the project in Xcode
```

- `Keepwell.xcodeproj` is **generated** from [`project.yml`](project.yml) and is not committed. Run
  `make generate` after changing `project.yml` or adding files.
- To sign for a device, create `Configs/Local.xcconfig` (git-ignored) from
  `Configs/Local.xcconfig.example` with your `DEVELOPMENT_TEAM`. With a personal (free) team, also
  set `APP_ENTITLEMENTS` as that file shows: it drops Sign in with Apple and associated domains but keeps the App Group, which
  the widgets need to read the app's data.
- Design material lives in `design/` **locally only** and is never committed (it is git-ignored).
  Ask the team for it and place it under `design/keepwell-design/`.

## Commands

| Command                      | What it does                                              |
| ---------------------------- | --------------------------------------------------------- |
| `make bootstrap`             | Install tools (mise), generate the project, install hooks |
| `make generate`              | Regenerate `Keepwell.xcodeproj` with XcodeGen             |
| `make open`                  | Generate and open the project                             |
| `make run`                   | Build, install and launch the app on the simulator        |
| `make lint`                  | `swiftformat --lint` + `swiftlint --strict`               |
| `make format`                | Format code and apply SwiftLint autocorrections           |
| `make build`                 | Build the app for the simulator                           |
| `make test`                  | Package unit tests + UI tests, with coverage              |
| `make test-unit`             | Unit tests only (used by the pre-push hook)               |
| `make test-ui`               | UI tests only                                             |
| `make test-record-snapshots` | Re-record snapshot test references                        |
| `make resolve`               | Re-resolve SPM packages and update `Package.resolved`     |
| `make clean`                 | Delete `build/` and the generated project                 |

The simulator is picked by `scripts/simulator-destination.sh` (defaults to *iPhone 17e*; override
with `SIMULATOR_NAME="iPhone 17" make test`).

## Layout

```
App/                 App target (entry point, environment, resources, entitlements)
Widgets/             WidgetKit extension
UITests/             UI tests (XCTest)
Packages/
  Core/              Navigation (AppRouter) and formatters (CurrencyFormatter)
  DesignSystem/      Tokens (colors, Inter typography, spacing, radii, shadows) + base components
  Domain/            Shared domain kernel: DomainError, TransactionKind, ISO 4217 (Foundation only)
  Persistence/       SwiftData + CloudKit (private database), versioned schema
  Features/          One folder per feature, split into Domain / Data / Presentation targets
Configs/             Per-environment .xcconfig files
scripts/             Support scripts (commit validation, simulator, SwiftLint in Xcode)
```

Module dependencies: `App → Features → (Core, DesignSystem, Domain)`, `App → Persistence → Features (Data)`.

## Architecture

Clean Architecture + MVVM, organized by feature. Each feature in `Packages/Features/Sources/<Feature>/`
is split into three SwiftPM targets so the compiler enforces the boundaries:

- **Domain** — entities (immutable structs), repository protocols and use cases. Foundation only.
- **Data** — SwiftData `@Model` records, mappers and repository implementations.
- **Presentation** — `@Observable` view models (talk to use cases only) and SwiftUI views.

`App/Sources/DI/AppContainer` wires Data → Domain → Presentation; `App/Sources/Navigation/RootView`
owns the `NavigationStack` driven by `AppRouter`. Money is always `Decimal` + ISO 4217 code.
SwiftLint custom rules fail the build on layer violations. Full rules: [`CLAUDE.md`](CLAUDE.md).

## Environments

| Configuration | Bundle ID                           | Name             | Use                                         |
| ------------- | ----------------------------------- | ---------------- | ------------------------------------------- |
| Debug         | `com.stevenmendez.keepwell.debug`   | Keepwell Dev     | Local development                           |
| Staging       | `com.stevenmendez.keepwell.staging` | Keepwell Staging | QA / TestFlight (*Keepwell Staging* scheme) |
| Release       | `com.stevenmendez.keepwell`         | Keepwell         | App Store                                   |

Values live in `Configs/*.xcconfig`. `API_BASE_URL` points the app at the Keepwell API; left empty,
the app is local-only and onboarding and Settings offer no account.

## Quality and tests

- **SwiftFormat** owns formatting; **SwiftLint** owns quality rules. Overlapping style rules are
  disabled in SwiftLint so the two never conflict.
- SwiftLint also runs as an Xcode build phase: warnings only in Debug; it fails Staging/Release builds.
- **Swift Testing** for each package's tests; **XCTest** for UI tests.
- **Snapshot tests** with swift-snapshot-testing. References are recorded on *iPhone 17e* at 2x scale;
  for intentional visual changes run `make test-record-snapshots`, review the images and commit them.
- Coverage is gathered in the `Keepwell` scheme and CI publishes the report in the job summary.

## Branches and commits

- `main` — production. `staging` — QA/TestFlight. `develop` — integration (default branch for work).
- Work branches from `develop`: `feat/*`, `fix/*`, `chore/*`.
- Flow: `feat/x → develop → staging → main` through pull requests.
- [Conventional Commits](https://www.conventionalcommits.org) are required (enforced by the
  `commit-msg` hook and by the PR title check in CI):

  ```
  <type>(<optional scope>)!: <description>
  types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
  ```

Hooks (Lefthook): `pre-commit` → SwiftFormat + SwiftLint on staged files; `commit-msg` →
Conventional Commits validation; `pre-push` → build + unit tests. See [CONTRIBUTING.md](CONTRIBUTING.md).

## CI

GitHub Actions ([`.github/workflows/ios-ci.yml`](.github/workflows/ios-ci.yml)) runs lint, build and tests on
the `xcode-27` runner, explicitly selecting Xcode 27.1 with `xcode-select`, for pull requests and pushes
to `develop`, `staging` and `main`. [`pr-title.yml`](.github/workflows/pr-title.yml) validates the PR
title. Dependabot updates SPM packages and GitHub Actions weekly against `develop`.

## Dependencies

Native APIs are preferred (SwiftData, CloudKit, OSLog, LocalAuthentication, WidgetKit, AppIntents).
External packages (minimum version via `from:`; exact versions pinned in `Package.resolved`):

| Package                                                                                     | From   | Purpose                              |
| ------------------------------------------------------------------------------------------- | ------ | ------------------------------------ |
| [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | 1.19.7 | Snapshot tests (tests only)          |
| [pointfreeco/swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump)           | 1.7.3  | Readable diffs in tests (tests only) |

Non-code assets: the **Inter 4.1** font (SIL Open Font License 1.1) is bundled in
`Packages/DesignSystem/Sources/DesignSystem/Resources/Fonts`.

Any new dependency must be justified in this section before it is added.
