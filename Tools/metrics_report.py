"""AeroStrike live metrics report.

Pulls the MetricsServer counters (DataStore "AS_Metrics") through Open Cloud and prints a
daily report: players, session length, new-player funnel, retention cohorts, revenue,
devices and errors, each against the launch targets in Docs/LaunchPlan.md.

    uv run --no-project python Tools/metrics_report.py            # last 7 days
    uv run --no-project python Tools/metrics_report.py --days 14
    uv run --no-project python Tools/metrics_report.py --dir dumps  # from saved JSON entries
    uv run --no-project python Tools/metrics_report.py --save dumps # also save raw entries

Needs ROBLOX_API_KEY in .env with DataStore read access to universe 10777495043
(read only inside this script; never printed). --dir reads <key>.json files instead.
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request, urllib.error
from datetime import datetime, timezone

UNIVERSE = 10777495043
STORE = "AS_Metrics"
SHARDS = 8
FTUE = ["spawned_on_catapult", "launched", "guns", "lock_and_fire", "first_upgrade", "go_live", "first_kill_or_mission"]
SESSION = ["join", "loaded", "spawned", "launched", "first_shot", "first_lock", "first_kill", "first_bank", "first_upgrade"]
BUCKETS = ["lt1", "1_3", "3_5", "5_10", "10_20", "20_40", "40p"]

def api_key():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(root, ".env")
    if os.environ.get("ROBLOX_API_KEY"):
        return os.environ["ROBLOX_API_KEY"]
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line.startswith("ROBLOX_API_KEY"):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None

def fetch(key, entry):
    q = urllib.parse.urlencode({"datastoreName": STORE, "entryKey": entry})
    url = f"https://apis.roblox.com/datastores/v1/universes/{UNIVERSE}/standard-datastores/datastore/entries/entry?{q}"
    req = urllib.request.Request(url, headers={"x-api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        body = e.read().decode("utf-8", "replace")[:200]
        sys.exit(f"Open Cloud error {e.code} for {entry}: {body}\n(Does the API key have DataStore read access for this experience?)")

def load(entry, key, src_dir, save_dir):
    if src_dir:
        p = os.path.join(src_dir, entry + ".json")
        if not os.path.exists(p):
            return None
        return json.load(open(p, encoding="utf-8"))
    v = fetch(key, entry)
    if v is not None and save_dir:
        os.makedirs(save_dir, exist_ok=True)
        json.dump(v, open(os.path.join(save_dir, entry + ".json"), "w", encoding="utf-8"))
    return v

def merged(prefix, day, key, src_dir, save_dir):
    out = {}
    for s in range(SHARDS):
        v = load(f"{prefix}{day}_s{s}", key, src_dir, save_dir)
        if not isinstance(v, dict):
            continue
        for k, n in v.items():
            if k.startswith("_") or not isinstance(n, (int, float)):
                continue
            out[k] = max(out.get(k, 0), n) if k.startswith("max_") else out.get(k, 0) + n
    return out

def pct(a, b):
    return f"{100.0 * a / b:5.1f}%" if b else "   - "

def flag(ok):
    return "OK " if ok else "LOW"

def date_of(day):
    return datetime.fromtimestamp(day * 86400, tz=timezone.utc).strftime("%a %d %b")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--dir"); ap.add_argument("--save")
    a = ap.parse_args()
    key = None if a.dir else api_key()
    if not a.dir and not key:
        sys.exit("No ROBLOX_API_KEY found (.env or environment). Or pass --dir with saved entries.")
    today = int(time.time() // 86400)
    days = list(range(today - a.days + 1, today + 1))
    D = {d: merged("d", d, key, a.dir, a.save) for d in days}
    C = {d: merged("c", d, key, a.dir, a.save) for d in days}

    print(f"AeroStrike metrics, {date_of(days[0])} to {date_of(days[-1])} (UTC; today is partial)\n")
    print("== Daily ==")
    print(f"{'day':<11}{'DAU':>6}{'new':>6}{'ret':>6}{'avgCCU':>8}{'peakSrv':>8}{'sess':>6}{'avg min':>8}{'new min':>8}{'robux':>7}{'payers':>7}{'conv':>7}")
    tot = {}
    for d in days:
        c = D[d]
        for k, v in c.items():
            tot[k] = max(tot.get(k, 0), v) if k.startswith("max_") else tot.get(k, 0) + v
        sess = c.get("sessions", 0); ended = sum(c.get("sb_" + b, 0) for b in BUCKETS)
        avg = c.get("sess_secs", 0) / ended / 60 if ended else 0
        navg = c.get("sess_new_secs", 0) / c.get("sess_new_n", 1) / 60 if c.get("sess_new_n") else 0
        ccu = c.get("player_mins", 0) / 1440
        print(f"{date_of(d):<11}{c.get('dau',0):>6}{c.get('new',0):>6}{c.get('returning',0):>6}{ccu:>8.1f}{c.get('max_server_players',0):>8}"
              f"{sess:>6}{avg:>8.1f}{navg:>8.1f}{c.get('robux',0):>7}{c.get('payers',0):>7}{pct(c.get('payers',0), c.get('dau',0)):>7}")

    ended = sum(tot.get("sb_" + b, 0) for b in BUCKETS)
    avg_all = tot.get("sess_secs", 0) / ended / 60 if ended else 0
    nn = tot.get("sess_new_n", 0)
    avg_new = tot.get("sess_new_secs", 0) / nn / 60 if nn else 0
    vers = sorted(((k[4:], v) for k, v in tot.items() if k.startswith("ver:")), key=lambda x: -int(x[0]) if x[0].isdigit() else 0)
    if vers:
        print("\nSessions by published version: " + ", ".join(f"v{k} {v}" for k, v in vers))
    print("\n== Session length (all sessions / new players' sessions) ==")
    for b in BUCKETS:
        print(f"  {b.replace('_','-').replace('lt1','<1').replace('40p','40+'):>6} min  {pct(tot.get('sb_'+b,0), ended)}   {pct(tot.get('sbn_'+b,0), nn)}")
    print(f"  average: {avg_all:.1f} min (new players {avg_new:.1f})   target 10+  [{flag(avg_all >= 10)}]")

    new = tot.get("new", 0)
    print(f"\n== New-player onboarding funnel ({new} new players) ==   target 70%+ reach go_live")
    prev = None
    for s in FTUE:
        n = tot.get("n_ftue_" + s, 0)
        drop = f"  (-{pct(prev - n, prev).strip()} from previous)" if prev else ""
        print(f"  {s:<24}{n:>6}  {pct(n, new)}{drop}")
        prev = n
    print("\n== New-player session funnel ==")
    for s in SESSION:
        n = tot.get("n_session_" + s, 0)
        print(f"  {s:<24}{n:>6}  {pct(n, new)}")

    print("\n== Retention by cohort (players returning on day N / new that day) ==   targets D1 15%+ (great 25%+), D7 5%+")
    print(f"  {'cohort':<11}{'new':>6}{'D1':>8}{'D2':>8}{'D3':>8}{'D7':>8}{'D14':>8}{'payers':>8}")
    for d in days:
        c = C[d]
        n = c.get("new", 0)
        if not n:
            continue
        cells = []
        for k in (1, 2, 3, 7, 14):
            cells.append(pct(c.get(f"d{k}", 0), n) if today - d >= k else "    .")
        print(f"  {date_of(d):<11}{n:>6}" + "".join(f"{x:>8}" for x in cells) + f"{c.get('payers',0):>8}")

    dau = tot.get("dau", 0)
    print("\n== Revenue ==")
    print(f"  Robux (list price) {tot.get('robux',0)}   purchases {tot.get('buys',0)}   payer-sessions {tot.get('payers',0)}"
          f"   conversion {pct(tot.get('payers',0), dau).strip()} (target 1-3%)   ARPDAU {tot.get('robux',0)/dau if dau else 0:.2f} R$")
    skus = sorted(((k[4:], v) for k, v in tot.items() if k.startswith("buy_")), key=lambda x: -x[1])
    if skus:
        print("  by item: " + ", ".join(f"{k} x{v}" for k, v in skus))
    views = tot.get("u_shop_shop_open", 0); prompts = tot.get("u_shop_purchase_prompt", 0)
    print(f"  shop funnel (sessions): opened {views}, viewed product {tot.get('u_shop_product_view',0)}, prompted {prompts}, bought {tot.get('u_shop_purchase_success',0)}")

    print("\n== Devices (sessions / new players) ==")
    devs = {k: tot.get("dev_" + k, 0) for k in ("Touch", "KBM", "Gamepad")}
    dt = sum(devs.values())
    for k, v in devs.items():
        print(f"  {k:<8}{pct(v, dt)}   new {pct(tot.get('devn_'+k,0), sum(tot.get('devn_'+x,0) for x in devs))}")

    sess = tot.get("sessions", 0) or 1
    def pref(prefix):
        return sorted(((k[len(prefix):], v) for k, v in tot.items() if k.startswith(prefix)), key=lambda x: -x[1])
    def line(items, top=10, fmt=lambda k, v: f"{k} {v}"):
        return ", ".join(fmt(k, v) for k, v in items[:top]) or "-"

    print("\n== New players: time to each milestone (avg, from join) ==")
    for e in ["session_loaded", "session_spawned", "ftue_launched", "session_first_shot", "ftue_guns", "session_first_lock",
              "ftue_lock_and_fire", "session_first_kill", "ftue_go_live", "session_first_bank", "session_first_upgrade"]:
        n = tot.get("ttn_" + e, 0)
        if n:
            print(f"  {e:<24}{tot.get('tt_' + e, 0) / n:7.0f} s   ({n} players)")
    rk = sorted(((int(k[8:]), v) for k, v in tot.items() if k.startswith("ttn_rank") and k[8:].isdigit()))
    if rk:
        print("  rank-ups: " + ", ".join(f"R{r} {tot.get(f'tt_rank{r}', 0) / v / 60:.1f}m ({v})" for r, v in rk))

    print("\n== Session survival (share of sessions still playing at minute N: all / new) ==")
    allm = {int(k[3:]): v for k, v in tot.items() if k.startswith("sm_") and k[3:].isdigit()}
    newm = {int(k[4:]): v for k, v in tot.items() if k.startswith("smn_") and k[4:].isdigit()}
    ta, tn = sum(allm.values()), sum(newm.values())
    for m in (1, 2, 3, 5, 7, 10, 15, 20, 30):
        a_ = sum(v for k, v in allm.items() if k >= m); n_ = sum(v for k, v in newm.items() if k >= m)
        print(f"  {m:>3} min  {pct(a_, ta)}   {pct(n_, tn)}")

    print("\n== Where new players leave ==")
    qs = pref("quitn_step:"); qt = sum(v for _, v in qs)
    print("  last milestone reached: " + line(qs, 12, lambda k, v: f"{k} {pct(v, qt).strip()}"))
    qp = pref("quitn_phase:"); qpt = sum(v for _, v in qp)
    print("  state when leaving:     " + line(qp, 6, lambda k, v: f"{k} {pct(v, qpt).strip()}"))
    print(f"  left within 25 s of dying: {pct(tot.get('quitn_after_death', 0), qt).strip()} of new / {pct(tot.get('quit_after_death', 0), sum(v for _, v in pref('quit_phase:'))).strip()} of all")
    re_ = pref("rank_endn:")
    print("  rank at end of first session: " + line(sorted(re_, key=lambda x: int(x[0]) if x[0].isdigit() else 0), 15, lambda k, v: f"R{k} x{v}"))

    print("\n== New-player funnel by device ==")
    devs3 = ("Touch", "KBM", "Gamepad")
    print(f"  {'step':<24}" + "".join(f"{d:>10}" for d in devs3))
    base = {d: tot.get(f"devn_{d}", 0) for d in devs3}
    print(f"  {'players':<24}" + "".join(f"{base[d]:>10}" for d in devs3))
    for e in ["ftue_launched", "ftue_guns", "ftue_lock_and_fire", "ftue_go_live", "session_first_kill", "session_first_bank", "session_first_upgrade"]:
        print(f"  {e:<24}" + "".join(f"{pct(tot.get(f'nd_{d}_{e}', 0), base[d]):>10}" for d in devs3))
    print("  avg session min: " + ", ".join(f"{d} {tot.get('sess_secs_dev:' + d, 0) / tot['sess_n_dev:' + d] / 60:.1f}" for d in devs3 if tot.get("sess_n_dev:" + d)))

    print("\n== Sorties (one life = launch to death) ==")
    so = tot.get("m_sortie", 0); son = tot.get("mn_sortie", 0)
    deaths = sum(v for k, v in tot.items() if k.startswith("death:"))
    print(f"  sorties {so} (new players {son}), per session {so / sess:.1f}   avg time alive {tot.get('m_sortie_secs', 0) / max(deaths, 1):.0f} s"
          f" (new {tot.get('mn_sortie_secs', 0) / max(sum(v for k, v in tot.items() if k.startswith('deathn:')), 1):.0f} s)   target new 90 s+")
    SB = ["lt15", "15_30", "30_60", "1_2m", "2_4m", "4_8m", "8mp"]
    slt = sum(tot.get("sl_" + b, 0) for b in SB); slnt = sum(tot.get("sln_" + b, 0) for b in SB)
    print("  time alive:     " + "  ".join(f"{b} {pct(tot.get('sl_' + b, 0), slt).strip()}/{pct(tot.get('sln_' + b, 0), slnt).strip()}" for b in SB) + "   (all/new)")
    skt = sum(tot.get("sk_" + b, 0) for b in ("0", "1", "2", "3p")); sknt = sum(tot.get("skn_" + b, 0) for b in ("0", "1", "2", "3p"))
    print("  kills per life: " + "  ".join(f"{b} {pct(tot.get('sk_' + b, 0), skt).strip()}/{pct(tot.get('skn_' + b, 0), sknt).strip()}" for b in ("0", "1", "2", "3p")))
    dc = pref("death:"); dct = sum(v for _, v in dc)
    print("  death causes:   " + line(dc, 10, lambda k, v: f"{k} {pct(v, dct).strip()}"))
    dn = pref("deathn:"); dnt = sum(v for _, v in dn)
    print("  ...new players: " + line(dn, 10, lambda k, v: f"{k} {pct(v, dnt).strip()}"))
    kb = pref("killed_by:"); kbt = sum(v for _, v in kb)
    print("  shot down by:   " + line(kb, 10, lambda k, v: f"{k} {pct(v, kbt).strip()}"))
    kbn = pref("killedn_by:")
    print("  ...new players: " + line(kbn, 10))
    rb = {}
    for k, v in tot.items():
        if k.startswith("death_rb:"):
            _, b, c = k.split(":", 2); rb.setdefault(b, []).append((c, v))
    for b in sorted(rb):
        items = sorted(rb[b], key=lambda x: -x[1])
        print(f"  deaths {b:<6} " + line(items, 6))

    print("\n== Combat mechanics ==")
    gs, gh = tot.get("m_gun_shots", 0), tot.get("m_gun_hits", 0)
    mf, mu, mh = tot.get("m_msl_fired", 0), tot.get("m_msl_unguided", 0), tot.get("m_msl_hit", 0)
    print(f"  gun accuracy {pct(gh, gs).strip()} ({gh}/{gs} rounds; new {pct(tot.get('mn_gun_hits', 0), tot.get('mn_gun_shots', 0)).strip()})")
    print(f"  missiles: {mf} locked + {mu} unguided, hit rate {pct(mh, mf + mu).strip()} (new: {tot.get('mn_msl_fired', 0)} locked, {tot.get('mn_msl_unguided', 0)} unguided, {tot.get('mn_msl_hit', 0)} hits)")
    print(f"  incoming missiles per life: AI {tot.get('m_msl_incoming_ai', 0) / max(so, 1):.2f}, players {tot.get('m_msl_incoming_pvp', 0) / max(so, 1):.2f}"
          f"   (new players: AI {tot.get('mn_msl_incoming_ai', 0) / max(son, 1):.2f})")
    fu, fs = tot.get("m_flare_used", 0), tot.get("m_flare_saved", 0)
    print(f"  flares used {fu}, missiles decoyed {fs} ({fs / fu if fu else 0:.2f} per flare); new players used {tot.get('mn_flare_used', 0)}")
    print("  kills by weapon: " + line(pref("kill:")))
    print("  kills on:        " + line(pref("kill_t:")))
    print("  events per session: " + ", ".join(f"{e} {tot.get('e_' + e, 0) / sess:.2f}" for e in (
        "missile_evaded", "ace_evade", "multi_kill", "bank", "landing", "mission_join", "mission_complete", "boss_kill",
        "bounty_claimed", "playtime_gift", "challenge_done", "sonic_boom", "squad_join", "code_redeemed")))
    mc = pref("e_mission_complete:")
    if mc:
        print("  missions completed: " + line(mc))

    print("\n== Jets ==")
    jets = sorted({k.split(":", 1)[1] for k in tot if k.startswith(("sortie_jet:", "kill_jet:", "death_jet:"))})
    for j in jets:
        sj, kj, dj = tot.get("sortie_jet:" + j, 0), tot.get("kill_jet:" + j, 0), tot.get("death_jet:" + j, 0)
        print(f"  {j:<12} sorties {sj:>5}  kills {kj:>5}  deaths {dj:>5}  K/D {kj / dj if dj else kj:.2f}")
    ju = pref("jet_unlock:")
    if ju:
        print("  unlocks: " + line(ju) + "   timing: " + line(pref("jet_unlock_mins:"), 12))

    print("\n== Economy (cash) ==")
    print("  earned by reward:  " + line(pref("earn:"), 12))
    print("  all cash sources:  " + line(pref("cash_in:"), 12))
    print("  cash sinks:        " + line(pref("cash_out:"), 12))
    ru = sorted(((int(k), v) for k, v in pref("rank_up:") if k.isdigit()))
    if ru:
        print("  rank-ups reached:  " + ", ".join(f"R{r} x{v}" for r, v in ru))
    print("  shop item views:   " + line(pref("e_shop_product_view:")))
    print("  purchase prompts:  " + line(pref("e_shop_purchase_prompt:")) + "   cancelled: " + line(pref("e_purchase_cancelled:")))
    print("  upgrades bought:   " + line(pref("e_session_first_upgrade:")))

    errs = sorted(((k, v) for k, v in tot.items() if k.startswith("err_")), key=lambda x: -x[1])
    print(f"\n== Errors ({sum(v for _, v in errs)} total) ==")
    for k, v in errs[:15]:
        print(f"  {v:>6}  {'server' if k.startswith('err_s') else 'client'}  {k.split(':',1)[1]}")
    if not errs:
        print("  none")

if __name__ == "__main__":
    main()
