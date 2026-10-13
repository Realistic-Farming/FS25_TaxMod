# Changelog

All notable changes to FS25_TaxMod will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Changelog tracking for this mod begins **2026-08-22** under the suite-wide ruling
(see the ecosystem ledger, entry for Arissani and Wizard). Prior history lives in
the repo's git history and README.

---

## [Unreleased]

## [1.2.0.0] - 2026-10-12

> **This is not a final release.** It gives everyone, testers and players, new or returning, everything we have built so far, so nobody has to wait on an old version any longer. The Realistic Farming suite is far from done: we are still building and expanding every mod, and completing it could take months, possibly a year. Expect changes and rough edges along the way, and please report anything that looks wrong.

### Fixed
- **The yearly tax cycle runs again.** The December advisory and the March payment never fired, because the mod read a calendar field the game does not have. Tax now follows the game's named months in either hemisphere, and the year's bill is collected once in March.
- Multiplayer (with Network Sync): players in a hosted game see the server's tax settings and their own farm's tax record, and get their daily and annual tax notices from it. The HUD's annual rate shows as a whole percentage.
- Converting a multiplayer save to single player keeps each farm's tax history separate, so nothing is charged twice.
- Tax settings are saved with the game reliably.
- The mod's description, settings and Esc texts read correctly in every language, Ukrainian and Polish included, and the page legend shows a plain dot between page names.

### Added
- A Tax HUD show/hide toggle in the Control Center.
- The emergency loan in Income Mod can read the tax you will owe, so a loan offer accounts for the annual bill.

### Changed
- The Realistic Farming Esc menu pages are shared with the other suite mods: scrollable breed tables, the Pro Staff page and the dairy barn cards work on any host, and the side panel's text is laid out in lines.

### Fixed
- RSF-F201 PLAYER-lifetime companion: the TM_TOGGLE_HUD wrapper installs once per session (no more rewrap on every client load) and is no longer restored on unload, which could unhook a later mod's wrapper.

## [1.1.6.0] - 2026-08-26

### Fixed
- Settings path nil-guard: an early settings save during the shared I3D load could concatenate the savegame folder path before it existed and abort the load (the full-suite load crash, SF issues #857/#858). The path is now nil-guarded (PR #34).
- Cleared the TM_TOGGLE_HUD default binding so the input convention ships clean (API-6, PR #35).
- Hot-reload conformance, suite-edit/vehicle input, and docs truth corrections (PR #38).

### Added
- Option-Scaling Spine adoption on the economy dial (PR #36).
- Base-game HUD extension styling, width resizing, and factory layout defaults (PR #37).
- Changelog file established (suite ruling 2026-08-22).

## [1.1.5.59] - 2026-08-22

- First entry under changelog tracking.
