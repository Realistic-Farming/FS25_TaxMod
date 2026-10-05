# Roadmap: FS25_TaxMod

> Ecosystem role: **Markets and Economy** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline.
> Forward-looking only. Shipped history lives in CHANGELOG.md and the releases.

## How to use this file
- Populate the milestones below from the audit baseline once it lands.
- Each item should be small enough to map to a `TODO.md` entry.
- Keep it honest: near-term is committed, mid-term is intended, long-term is aspirational.

## Current baseline
- Version at baseline: v1.1.3.0
- Audit reference: ecosystem-dev-tracking Point 1-5 (FS25_TaxMod, 2026-06-30)
- Baseline date: 2026-06-30

## Near-term (next release cycle)
- [x] API-6 input convention: clear default bindings (2026-08-18): `TM_TOGGLE_HUD` shipped `T` as a default (a collision with chat and the FarmTablet key history). Removed so the player assigns it in the game's control settings (rule 1 of the Input Convention). Action stays registered and rebindable.
- [x] Load-crash nil guard on the settings path (2026-08-18): `getSettingsPath()` guarded on `missionInfo` existing but not on `missionInfo.savegameDirectory`, which is nil during the shared I3D load, so any early `saveSettings()`/`loadSettings()` call threw "attempt to concatenate nil with string" and aborted the load (reported on SoilFertilizer #857 / #858, the crash with the full RF suite). The guard now covers `savegameDirectory`, and both callers already no-op on a nil path. One line.
- [x] MP tax bug (F15): DONE on development (commit 8ff9989d). Annual-tax `addMoney` gated on `getIsServer`; `applyDailyTax` only accumulates. Re-verify the release asset matches dev HEAD (asset modDesc was mislabeled 1.1.4.1).
- [x] StateLedger `TaxMod_Data` bridge live (delegate-when-present); `modSettings/` save kept as the safety copy. Shipped v1.1.5.0. (Fully retiring the FS22 path is a later cleanup.)
- [~] SettingsHub: 5 settings registered (selfPersisted), shipped v1.1.5.0; removing TaxSettingsUI.lua + UIHelper.lua (ESC injection) still open.
- [x] 2026-07-26 bug sweep: TX-001 / TX-002 fixed and merged to main.

## Mid-term (this season)
- [ ] NetworkSync channel `TaxMod_Sync` for settings broadcast on admin change. Not built yet.
- [x] MasterHUD `TaxMod_HUD` registered (delegate-when-present; TaxHUD keeps its own draw/update/mouse logic). Shipped v1.1.5.0.
- [ ] Decide the fate of `returnPercentage` (vestigial in the annual model).

## Long-term / aspirational
- [ ] Richer tax model (brackets, deductions, or period options) without breaking MP correctness.

## Cross-mod / ecosystem dependencies
- [~] Bedrock migrations: 3/4 done (StateLedger + MasterHUD + SettingsHub, v1.1.5.0); NetworkSync remaining.
- [ ] FarmTablet TaxApp (reads `g_currentMission.taxManager`).

## Deferred / parked
- Consuming a peer earnings API instead of reading `farm.money` directly: parked; direct read is correct and simpler for v1.

## 2026-08-14 (Fred): F160 - the irrigation-expense day index matches SCS's corrected schedule
- [x] CropStressIrrigationExpense mirrored SCS's old day-of-week read (env.currentDayInPeriod, pinned at 1 on a default save). It now derives the index from the monotonic day modulo 7, matching SCS's F160 fix, so the accrual lands on the days SCS actually runs. DAILY_DEPRECIATION_PER_SYSTEM stays 0 (balance-pass number).

## 2026-10-04 (Fred): the shared RF Esc door at the suite's STOCK page set (Wizard, #62)

- [x] The four shared Esc door files (`xml/gui/RfPdaMenuPage.xml`, `src/gui/RfPdaMenuPage.lua`, `src/gui/RfEscModules.lua`, `xml/gui/rfEscProfiles.xml`) are at the set every door mod carries, byte-same in all ten (Wizard's STOCK page chain build, #62, merged at 3c6cf4c4): wider sheet cells, the explanation band at up to four lines, the ids and callbacks StockGuard's STOCK page uses (inert without StockGuard), the hidden ids and profiles of DairyCore's herd-advisory panel, ProStaff in the closed-module list, and Soil Fertilizer's AUTO target card kept.
- The door's in-game check is TESTING row 420. Docs by Fred's catch-up, on Tyson's word of 2026-10-04.

## 2026-10-05 (Fred): the Esc side panel's info box clear of the selected tab (Wizard, #65)

- [x] The shared Esc door file `xml/gui/RfPdaMenuPage.xml`, byte-same in all ten door mods (Wizard, #65, merged at dde50264): the side info boxes (`rfSideInfoShell`, `wcSideInfoShell`, `mdSideInfoShell`, `csSideInfoShell`) take an explicit position and size, 16 px further right and 16 px narrower (384 to 368 px), so the dark box starts clear of the selected tab's lime edge and its right edge stays where it was. The side text bodies narrow by the same 16 px, to 352 px (the main side text, from 368) and 348 px (the Worker Costs and Market Dynamics side help, from 364), so the text starts 16 px further right and each line ends where it did.
- The change's in-game check is TESTING row 444. Docs by Fred's catch-up, on Tyson's word of 2026-10-05.
