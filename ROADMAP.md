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
- [x] MP tax bug (F15): DONE on development (commit 8ff9989d). Annual-tax `addMoney` gated on `getIsServer`; `applyDailyTax` only accumulates. Re-verify the release asset matches dev HEAD (asset modDesc was mislabeled 1.1.4.1).
- [ ] StateLedger migration to `TaxMod_Data`: retire the `modSettings/` subfolder save path and the FS22 createXMLFile/loadXMLFile usage.
- [ ] SettingsHub migration: register the 5 settings; remove TaxSettingsUI.lua + UIHelper.lua (the ESC-menu injection).

## Mid-term (this season)
- [ ] NetworkSync channel `TaxMod_Sync` for settings broadcast on admin change.
- [ ] MasterHUD registration of `TaxMod_HUD` (delegate-when-present; TaxHUD keeps its own draw/update/mouse logic).
- [ ] Decide the fate of `returnPercentage` (vestigial in the annual model).

## Long-term / aspirational
- [ ] Richer tax model (brackets, deductions, or period options) without breaking MP correctness.

## Cross-mod / ecosystem dependencies
- [ ] All four bedrock migrations (blocks on: StateLedger, NetworkSync, MasterHUD, SettingsHub).
- [ ] FarmTablet TaxApp (reads `g_currentMission.taxManager`).

## Deferred / parked
- Consuming a peer earnings API instead of reading `farm.money` directly: parked; direct read is correct and simpler for v1.
