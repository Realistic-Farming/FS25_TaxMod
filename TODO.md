# TODO: FS25_TaxMod

> Ecosystem role: **Markets and Economy** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit/baseline, kept current.
> Convention: `[ ]` open · `[~]` in progress · `[x]` done · `[!]` blocked. Newest at the top of each section.

## From the ecosystem audit (Arissani)
- [ ] Migrate save off the `modSettings/` subfolder and the FS22 createXMLFile/loadXMLFile API to StateLedger `TaxMod_Data`.
- [ ] Remove TaxSettingsUI.lua + UIHelper.lua (ESC-menu injection); SettingsHub owns settings.
- [ ] Decide: keep or remove `returnPercentage`.

## Bugs
- [!] CRITICAL (MP): `applyAnnualTax()` and `applyDailyTax()` lack a `getIsServer()` gate. In multiplayer `addMoney(-taxAmount)` fires on every client for the same farmId, so tax is deducted multiple times. Add the server gate.

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
