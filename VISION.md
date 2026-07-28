# Vision: FS25_TaxMod

> Ecosystem role: **Markets and Economy** · Part of the Realistic Farming connected suite
> Status: FILLED from the ecosystem audit (Point 1-5, ecosystem-map, notes).
> Last updated: 2026-07-08

## 1. One-line purpose
Recurring farm taxation: an annual (and optional daily) tax charged against the farm's finances, so profit carries an ongoing liability instead of just accumulating.

## 2. Problem it solves
FS25 has no taxation. Money accrues with zero ongoing cost, so once a farm is profitable there is nothing pulling against the balance. TaxMod adds a realistic recurring tax so wealth management and reinvestment actually matter.

## 3. Design pillars
- **Multiplayer-correct.** Tax deductions are server-authoritative. A period's tax is charged once for a farm, never once per connected client.
- **Finance-based.** The tax scales off the farm's own money/finances, read from base-game farm data.
- **Configurable rates.** Tax rate and cadence are settings; defaults stay reasonable.
- **Standard persistence.** State lives in the standard save surface, not a non-standard subfolder.

## 4. Role in the ecosystem
- Public handle on `g_currentMission.taxManager` (getfenv alias `g_TaxManager`), set in `Mission00.load`.
- Reads from (consumes): base-game farm finances via `g_farmManager:getFarmById(...).money` directly. It does NOT consume a peer economy API (it is not a confirmed consumer of getEarningsForFarm/getFertilizerSpendForFarm; that was architectural intent, not v1 behaviour).
- Read by (consumers): FarmTablet TaxApp, via the mission handle read contract.
- Core-API registration status (specced in Point 1-5, not yet wired):
  - StateLedger (save/load): planned, module `TaxMod_Data`. Replaces the non-standard `modSettings/FS25_TaxMod.xml` and the FS22 createXMLFile/loadXMLFile usage.
  - NetworkSync (MP state): planned, channel `TaxMod_Sync` (settings broadcast on admin change).
  - MasterHUD (overlays): planned, `TaxMod_HUD` (TaxHUD already owns its draw/update/mouse logic).
  - SettingsHub (admin settings): planned, 5 settings. Removes TaxSettingsUI.lua + UIHelper.lua (the ESC-menu injection).

## 5. Explicit non-goals
- Does not consume peer economy mods for its base. It reads farm money directly rather than another mod's earnings API.
- Not a subsidy or income system (that is IncomeMod). TaxMod only takes money.
- The HUD layout stays client-local.

## 6. Success criteria
- A period's tax is deducted exactly once per farm, correct in multiplayer.
- Persistence moves to the standard save surface; no reliance on a `modSettings/` subfolder that may not exist.
- Settings are admin-gated with no ESC-menu injection remaining after the SettingsHub move.

## 7. Open questions for the audit
- `returnPercentage` is still in the settings table and save surface but no longer drives the annual tax model. Keep for backward compat or remove?
- MasterHUD: TaxHUD already guards on `g_gui` visibility itself. Should MasterHUD suppress draws when the GUI is visible, or does each panel keep handling that?
