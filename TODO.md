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
