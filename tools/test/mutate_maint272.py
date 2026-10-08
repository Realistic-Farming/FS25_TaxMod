# MAINTENANCE row 272 mutation battery: TaxMod's server tax record reaches clients through NetworkSync
# (src/integrations/TaxNetworkSyncBridge.lua: the record written and read, the client apply, the own-farm mirror and
# notices, the stand-down; main.lua: the two ticks' stand-down, the dirty marks, the transient annual charge). Rows live
# in tools/test/lua/MAINT-272-tax_record_to_clients_test.lua.
#
# TARGETED (Tyson, 2026-09-25 and 2026-09-26, R-25a): the lines this PR changes, Bob's mutant list plus the rows this
# build added. Targeted runs only (Tyson, 2026-09-30): each mutant runs SELECTED, this PR's bench; the two other benches
# that load main.lua ran once, unmutated, as the PR's selection baseline. This repo's runner has no selection, so the
# script writes a filtered copy of run-tests.mjs beside it for the run and deletes it after. Run ONE mutant per call, in
# the foreground, and check free memory by hand right before each.
#
# The edit is proved to LAND (exact occurrence count) and the restore is proved by a hash. KILLED* means killed only by
# a Lua error or a raised group: a weak kill.
#
# Usage (from the repo root):
#        py tools/test/mutate_maint272.py <id>        one mutant (prefix match must be unique)
#        py tools/test/mutate_maint272.py --check     every anchor matches its count; runs nothing
#        py tools/test/mutate_maint272.py --baseline  the selected tests, unmutated
#        py tools/test/mutate_maint272.py --list
import hashlib, os, re, subprocess, sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def p(rel): return os.path.join(ROOT, rel)

MAIN = "main.lua"
BRIDGE = "src/integrations/TaxNetworkSyncBridge.lua"
HUD = "src/ui/TaxHUD.lua"

SELECTED = [
    "MAINT-272-tax_record_to_clients_test.lua",
]
FILTER_FROM = 'const testFiles = readdirSync(LUA_DIR).filter((f) => f.endsWith("_test.lua")).sort();'
FILTER_TO = ('const testFiles = readdirSync(LUA_DIR).filter((f) => f.endsWith("_test.lua") && '
             'process.env.MUTATE_SELECTED.split(",").includes(f)).sort();')

MUTATIONS = [
 ("M01-settings-unwritten", BRIDGE,
  [("    arr[#arr + 1] = tostring(s.taxRate or \"medium\")\n",
    "    arr[#arr + 1] = \"medium\"\n", 1)],
  "the record carries a fixed daily rate, not the server's (J1, H1)"),
 ("M02-farm-accrual-unwritten", BRIDGE,
  [("        arr[#arr + 1] = whole(ft.taxesAccumulatedAnnual)\n",
    "        arr[#arr + 1] = 0\n", 1)],
  "the record carries no farm accrual (J1, D1)"),
 ("M03-not-applied", BRIDGE,
  [("    if isServer() then return end   -- pure client only: the server's record is the source\n",
    "    do return end\n", 1)],
  "a client never applies the record, as before (J1 on)"),
 ("M04-applied-on-server", BRIDGE,
  [("    if isServer() then return end   -- pure client only: the server's record is the source\n",
    "", 1)],
  "a record reaching the server's own onReadState overwrites the server (G1)"),
 ("M05-local-key-overwritten", BRIDGE,
  [("    s.enabled          = arr[2] == true\n",
    "    s.enabled          = arr[2] == true\n    s.showStatistics   = arr[2] == true\n", 1)],
  "the apply writes a player-local key (L5)"),
 ("M06-daily-tick-not-gated", MAIN,
  [("    if not settings.enabled or not g_currentMission or (TaxNetworkSyncBridge and TaxNetworkSyncBridge.clientStandsDown()) then return end\n",
    "    if not settings.enabled or not g_currentMission then return end\n", 1)],
  "a synced client's own daily tick still runs: a second count and a second notice (D2, D4)"),
 ("M07-annual-tick-not-gated", MAIN,
  [("    if not settings.enabled or not g_currentMission or (TaxNetworkSyncBridge and TaxNetworkSyncBridge.clientStandsDown()) then return end  -- [row 272]\n",
    "    if not settings.enabled or not g_currentMission then return end\n", 1)],
  "a synced client's own annual tick still runs: a second annual notice (A4)"),
 ("M08-mirror-wrong-farm", BRIDGE,
  [("    pcall(function() ownId = g_currentMission:getFarmId() end)\n",
    "    ownId = 1\n", 1)],
  "the client mirrors the host's farm, not its own (J1, A4)"),
 ("M09-no-dirty-daily", MAIN,
  [("    if TaxNetworkSyncBridge then TaxNetworkSyncBridge.markDirty() end  -- [row 272]\nend\n",
    "end\n", 1)],
  "the daily tick marks nothing: the day waits for the next unrelated send (D1)"),
 ("M10-no-dirty-expense", MAIN,
  [("    if TaxNetworkSyncBridge then TaxNetworkSyncBridge.markDirty() end  -- [row 272] the ledger totals ride to clients\n",
    "", 1)],
  "recordExpense marks nothing (R1)"),
 ("M11-no-dirty-save", MAIN,
  [("    if TaxNetworkSyncBridge then TaxNetworkSyncBridge.markDirty() end  -- [row 272] every settings writer and the annual pass save\n",
    "", 1)],
  "saveSettings marks nothing: a settings change and the annual pass wait (H1, A4)"),
 ("M12-no-annual-charge", MAIN,
  [("        if anyBucketDue then ft.lastAnnualCharge = farmTax end  -- [row 272] the client's annual notice (not saved)\n",
    "", 1)],
  "the record carries no annual charge: the client's annual notice is lost (A4)"),
 ("M13-ledger-not-rebuilt", BRIDGE,
  [("        for farmId in pairs(farms) do farms[farmId] = nil end\n",
    "", 1)],
  "the client's stale ledger farms survive the apply (J1)"),
 ("M14-no-daily-notice", BRIDGE,
  [("    elseif acc > seen.acc then\n",
    "    elseif false then\n", 1)],
  "the client's daily notice and HUD record are lost (N3, D4)"),
 ("M15-notice-on-join", BRIDGE,
  [("    local seen = TaxNetworkSyncBridge._ownSeen\n",
    "    local seen = TaxNetworkSyncBridge._ownSeen or { farmId = ownId, acc = 0, year = year }\n", 1)],
  "the join's first apply notifies the whole accrual as one day (J1)"),
 ("M16-stands-down-without-sync", BRIDGE,
  [("    return TaxNetworkSyncBridge.active and g_currentMission ~= nil and not isServer()\n",
    "    return g_currentMission ~= nil and not isServer()\n", 1)],
  "a client with no NetworkSync stops its own ticks and freezes at its file (X6)"),
 ("M17-rate-as-float32", BRIDGE,
  [("    arr[#arr + 1] = whole((tonumber(s.annualTaxRate) or 0.05) * TaxNetworkSyncBridge.RATE_SCALE)\n", "    arr[#arr + 1] = tonumber(s.annualTaxRate) or 0.05\n", 1),
    ("    if rate ~= nil then s.annualTaxRate = rate / TaxNetworkSyncBridge.RATE_SCALE end\n", "    if rate ~= nil then s.annualTaxRate = rate end\n", 1)],
  "the annual rate rides as a fraction (Float32), as Bob found: 0.1 arrives as 0.100000001 (J1, I1)"),
 ("M18-ledger-fractional", BRIDGE,
  [("        arr[#arr + 1] = whole(fl.creditTotal)\n        arr[#arr + 1] = whole(fl.debitTotal)\n",
    "        arr[#arr + 1] = tonumber(fl.creditTotal) or 0\n        arr[#arr + 1] = tonumber(fl.debitTotal) or 0\n", 1)],
  "the ledger totals ride as fractions (Float32) (R1, I1)"),
 ("M19-hud-concatenates", HUD,
  [("    renderText(x + w, cy - tsNormal, tsNormal, TaxHUD.formatAnnualRate(taxMod.settings.annualTaxRate)) -- Display annual rate\n",
    "    renderText(x + w, cy - tsNormal, tsNormal, \"Annual Rate: \" .. (taxMod.settings.annualTaxRate * 100) .. \"%\") -- Display annual rate\n", 1)],
  "the HUD prints the raw rate again: 10.0% and 5.0000000745058% (U1)"),
]


def sha(b): return hashlib.sha256(b).hexdigest()


def read(rel):
    with open(p(rel), "rb") as f: return f.read()


def anchors(rel, edits):
    data = read(rel)
    crlf = b"\r\n" in data
    out = []
    for old, new, want in edits:
        o = old.encode("utf-8")
        n = new.encode("utf-8")
        if crlf:
            o = o.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            n = n.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        out.append((o, n, want, data.count(o)))
    return data, out


def run_suite():
    here = os.path.join(ROOT, "tools", "test")
    runner = open(os.path.join(here, "run-tests.mjs"), encoding="utf-8").read()
    if runner.count(FILTER_FROM) != 1:
        raise SystemExit("run-tests.mjs changed: the selection anchor is not found once")
    sel = os.path.join(here, "_mutate_selected_runner.mjs")
    with open(sel, "w", encoding="utf-8", newline="\n") as f:
        f.write(runner.replace(FILTER_FROM, FILTER_TO))
    try:
        env = dict(os.environ, MUTATE_SELECTED=",".join(SELECTED))
        r = subprocess.run(["node", "_mutate_selected_runner.mjs"], cwd=here, env=env,
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
    finally:
        os.remove(sel)
    out = r.stdout + r.stderr
    strip = lambda l: (re.sub(r"\x1b\[[0-9;]*m", "", l).strip().encode("ascii", "replace").decode("ascii"))
    lines = [strip(l) for l in out.splitlines()]
    fails = [l for l in lines if l.startswith("FAIL ") or "Lua error" in l or "crashed" in l]
    return r.returncode, fails, out


def main(argv):
    if not argv or argv[0] == "--list":
        for mid, rel, _, why in MUTATIONS: print(f"{mid:34s} {rel}  {why}")
        return 0
    if argv[0] == "--check":
        bad = 0
        for mid, rel, edits, _ in MUTATIONS:
            _, found = anchors(rel, edits)
            for i, (_, _, want, got) in enumerate(found):
                if got != want:
                    bad += 1
                    print(f"ANCHOR {mid} edit {i + 1}: want {want}, found {got}")
        print(f"{len(MUTATIONS)} mutants, {bad} bad anchor(s)")
        return 1 if bad else 0
    if argv[0] == "--baseline":
        rc, fails, out = run_suite()
        tail = [l for l in out.strip().splitlines() if l.strip()]
        print(re.sub(r"\x1b\[[0-9;]*m", "", tail[-1]) if tail else "(no output)")
        return rc
    picked = [m for m in MUTATIONS if m[0].startswith(argv[0])]
    if len(picked) != 1:
        print(f"'{argv[0]}' matches {len(picked)} mutants; name exactly one")
        return 2
    mid, rel, edits, why = picked[0]
    data, found = anchors(rel, edits)
    for i, (_, _, want, got) in enumerate(found):
        if got != want:
            print(f"{mid}: ANCHOR edit {i + 1} want {want}, found {got}; nothing changed")
            return 2
    before = sha(data)
    mutated = data
    for o, n, _, _ in found: mutated = mutated.replace(o, n)
    if mutated == data:
        print(f"{mid}: the edit changed nothing; not run")
        return 2
    try:
        with open(p(rel), "wb") as f: f.write(mutated)
        rc, fails, _ = run_suite()
    finally:
        with open(p(rel), "wb") as f: f.write(data)
    after = sha(read(rel))
    if after != before:
        print(f"{mid}: RESTORE FAILED ({before[:12]} -> {after[:12]})")
        return 3
    assertion = [f for f in fails if "Lua error" not in f and "crashed" not in f and not f.startswith("FAIL -")]
    verdict = "SURVIVED" if rc == 0 else ("KILLED" if assertion else "KILLED*")
    print(f"{mid}: {verdict}  ({why}); restored {before[:12]}")
    shown = assertion + [f for f in fails if f not in assertion]
    for f in shown[:12]: print("    " + f[:220])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
