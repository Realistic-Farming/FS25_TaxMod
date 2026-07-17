# TODO: FS25_TaxMod

> Ecosystem role: **Markets and Economy** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline, kept current.
> Convention: `[ ]` open · `[~]` in progress · `[x]` done · `[!]` blocked. Newest at the top of each section.

## From the ecosystem audit (Arissani)
- [ ] Migrate save off the `modSettings/` subfolder and the FS22 createXMLFile/loadXMLFile API to StateLedger `TaxMod_Data`.
- [ ] Remove TaxSettingsUI.lua + UIHelper.lua (ESC-menu injection); SettingsHub owns settings.
- [ ] Decide: keep or remove `returnPercentage`.

## Bugs
- [x] MP tax bug (F15): RESOLVED on development (commit 8ff9989d, 2026-07-01). The annual-tax `addMoney` is gated on `getIsServer` (main.lua:226); `applyDailyTax` only accumulates and moves no money. Note: the mislabeled pre-release asset (modDesc 1.1.4.1) predates this, so re-verify against dev HEAD before release.

## Features / enhancements
- [ ] Bedrock migration (StateLedger/NetworkSync/MasterHUD/SettingsHub) per Point 1-5.

## Cross-mod integration
- [x] SCS-011 irrigation-expense mirror: DONE (`src/integrations/CropStressIrrigationExpense.lua`, commit 9b19058). Reads the SCS B3.2b facade (`getIrrigationSystems` / `getIrrigationCostsEnabled`) once per in-game day and records ONE aggregated "Irrigation Operations" debit via `recordExpense` (bookkeeping only, no money moved; SCS already charges it, so no double-charge). Attributes to `g_currentMission:getFarmId()` (the same local player farm SCS's FinanceIntegration debits; corrects the brief's pivot-ownership OI-1). Depreciation wired but neutral at 0 (OI-2: needs a capital value + useful life from the balance pass). Deployed, not released; owes a single-host in-game smoke.
- [ ] TaxMod has NO self-test harness (verify gap). SCS-011 was verified via Lua 5.1 parse + the SCS-side getter test + in-game; stand up a `tools/test/` harness (mirror SoilFertilizer/SCS) before the next real logic build.
- [ ] StateLedger: `TaxMod_Data` (settings + stats + timer state, server-authoritative).
- [ ] NetworkSync: `TaxMod_Sync` (settings broadcast).
- [ ] MasterHUD: register `TaxMod_HUD` (delegate-when-present).
- [ ] SettingsHub: register the 5 settings.

## Docs / localization
- [ ] Keep all 26 languages in step for any new setting.
- [ ] Update README/version on each release.

## Blocked / waiting on
- [!] Bedrock migrations (waits on: adopting the four engines; SoilFertilizer is the reference pattern).
- [!] MasterHUD GUI-visibility suppression policy (waits on: audit answer on whether MasterHUD or each panel guards GUI visibility).
