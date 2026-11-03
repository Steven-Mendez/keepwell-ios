# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Project setup: XcodeGen, Debug/Staging/Release configurations, widgets extension, SwiftFormat,
  SwiftLint (with layer-boundary rules), Lefthook, GitHub Actions and Dependabot.
- Packages: `Core` (`AppRouter`, `CurrencyFormatter`), `DesignSystem` (tokens, Inter typography,
  `KWSurfaceCard`), `Domain` (shared kernel), `Persistence` (SwiftData + CloudKit, versioned schema)
  and `Features`.
- `AppContainer` composition root with init-based dependency injection.
