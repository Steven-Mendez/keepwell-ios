# Keepwell

Personal finance iOS app. Swift 6, SwiftUI, SwiftData. Domain must stay portable to TypeScript.

## Architecture: Clean Architecture + MVVM, by feature

Each feature lives in `Packages/Features/Sources/<Feature>/` as three SwiftPM targets:

| Folder                                             | Target                  | May depend on                      |
| -------------------------------------------------- | ----------------------- | ---------------------------------- |
| `Domain/` (`Entities`, `Repositories`, `UseCases`) | `<Feature>Domain`       | Foundation, shared `Domain`        |
| `Data/` (`Local`, `DTOs`, `Repositories`)          | `<Feature>Data`         | its Domain, SwiftData              |
| `Presentation/` (`ViewModels`, `Views`)            | `<Feature>Presentation` | its Domain, `Core`, `DesignSystem` |

- **Domain**: only `import Foundation`. Immutable `struct` entities, repository protocols, use cases
  (protocol + `Default…` struct).
- **Data**: implements Domain protocols. `@Model` records, `Codable` DTOs, mappers (`toDomain()` / `toEntity()`).
- **Presentation**: ViewModels are `@MainActor @Observable` and receive use case protocols only, never
  repositories or Data types.
- `Packages/Domain`: shared kernel (`DomainError`, `TransactionKind`). `Packages/Core`: `AppRouter`,
  `CurrencyFormatter`. `Packages/Persistence`: `ModelContainer` and versioned schema.
- `App/Sources/DI/AppContainer` is the composition root; `App/Sources/Navigation/RootView` owns the
  `NavigationStack`. Feature views expose navigation as closures.

## Rules

- Money is `Decimal` + ISO 4217 code. Never `Double`/`Float`. Never sum different currencies.
- `@Observable` only: no `ObservableObject`, `@Published`, `@StateObject`.
- `async/await` and typed throws: `throws(DomainError)`.
- Dependencies injected through `init` as protocols. No singletons.
- Tests use Swift Testing (`@Test`, `#expect`); XCTest only for UI tests.
- Comments explain *why*. No comments that restate code or say "sample/placeholder".
- Localization: English is the source language in code, with Spanish as the first translation
  (`en` + `es`). Every user-visible string lives in a `Localizable.xcstrings` catalog next to the
  target that uses it, keyed by its English text. Use `Text("…", bundle: #bundle)` in views and
  `String(localized: "…", bundle: #bundle)` wherever a `String` is needed. Domain never localizes;
  Presentation does. Default categories are stored in English and translated by id
  (`CategoryDisplay.name(of:)`). Dates and names follow `Locale.current`; money stays locale
  independent (`CurrencyFormatter`). New strings need their `es` entry before merging.
- Before committing: `make lint` and `make test-unit` pass.

## Git

- Branches: `main` (production), `staging` (QA), `develop` (integration). Work in `feat/*`, `fix/*`,
  `chore/*` from `develop`.
- Conventional Commits (`feat(scope): description`), enforced by the `commit-msg` hook.
- Update `CHANGELOG.md` under `[Unreleased]` with every user-visible change.
