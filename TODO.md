# TODO: FS25_TaxMod

> Ecosystem role: **Markets and Economy** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline, kept current.
> Convention: `[ ]` open · `[~]` in progress · `[x]` done · `[!]` blocked. Newest at the top of each section.

## From the ecosystem audit (Arissani)
- [x] StateLedger `TaxMod_Data` bridge live (delegate-when-present); own `modSettings/` save kept as the safety copy per the ecosystem pattern. Shipped v1.1.5.0. (Fully retiring the FS22 createXMLFile path is a later cleanup.)
- [~] SettingsHub bridged (selfPersisted, v1.1.5.0); removing TaxSettingsUI.lua + UIHelper.lua (ESC injection) is still open (ESC retained as the standalone fallback meanwhile).
- [ ] Decide: keep or remove `returnPercentage`.

## Bugs
- [x] MP tax bug (F15): RESOLVED on development (commit 8ff9989d, 2026-07-01). The annual-tax `addMoney` is gated on `getIsServer` (main.lua:226); `applyDailyTax` only accumulates and moves no money. Note: the mislabeled pre-release asset (modDesc 1.1.4.1) predates this, so re-verify against dev HEAD before release.

## Features / enhancements
- [~] Bedrock 3/4 built (delegate-when-present): StateLedger + MasterHUD + SettingsHub (v1.1.5.0). NetworkSync (`TaxMod_Sync`) still open.

## Cross-mod integration
- [x] SCS-011 irrigation-expense mirror: DONE + IN-GAME VERIFIED 2026-07-17 (`src/integrations/CropStressIrrigationExpense.lua`, commit 9b19058). Reads the SCS B3.2b facade (`getIrrigationSystems` / `getIrrigationCostsEnabled`) once per in-game day and records ONE aggregated "Irrigation Operations" debit via `recordExpense` (bookkeeping only, no money moved; SCS already charges it, so no double-charge). Attributes to `g_currentMission:getFarmId()` (the same local player farm SCS's FinanceIntegration debits; corrects the brief's pivot-ownership OI-1). Depreciation wired but neutral at 0 (OI-2: needs a capital value + useful life from the balance pass). Verified in-game: -€40 Irrigation Operations debit fired on the day change, no errors. Deployed, not released (batched). Soft follow-ups: confirm the amount equals SCS's actual daily deduction; check the `M0` month stamp in the ledger display.
- [ ] TaxMod has NO self-test harness (verify gap). SCS-011 was verified via Lua 5.1 parse + the SCS-side getter test + in-game; stand up a `tools/test/` harness (mirror SoilFertilizer/SCS) before the next real logic build.
- [x] StateLedger: `TaxMod_Data` bridge live (delegate-when-present). Shipped v1.1.5.0.
- [ ] NetworkSync: `TaxMod_Sync` (settings broadcast). Not built yet.
- [x] MasterHUD: `TaxMod_HUD` registered (delegate-when-present). Shipped v1.1.5.0.
- [x] SettingsHub: 5 settings registered (selfPersisted). Shipped v1.1.5.0.

## Docs / localization
- [ ] Keep all 26 languages in step for any new setting.
- [ ] Update README/version on each release.

## Blocked / waiting on
- [~] Bedrock migrations: 3/4 adopted (StateLedger/MasterHUD/SettingsHub, v1.1.5.0); NetworkSync remaining.
- [!] MasterHUD GUI-visibility suppression policy (waits on: audit answer on whether MasterHUD or each panel guards GUI visibility).
