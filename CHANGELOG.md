# Changelog

All notable changes to FS25_TaxMod will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Changelog tracking for this mod begins **2026-08-22** under the suite-wide ruling
(see the ecosystem ledger, entry for Arissani and Wizard). Prior history lives in
the repo's git history and README.

---

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
