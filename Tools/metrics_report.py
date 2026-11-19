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

    print("\n== Gameplay (events per session) ==")
    sess = tot.get("sessions", 0) or 1
    for ev in ("sortie_end", "missile_fired", "missile_hit", "flare_used", "crash", "g_loc", "fuel_empty", "bank", "mission_complete",
               "boss_kill", "multi_kill", "playtime_gift", "challenge_done", "code_redeemed", "squad_join", "prompt_favorite"):
        print(f"  {ev:<18}{tot.get('e_'+ev,0)/sess:7.2f}")
    deaths = sorted(((k.split(':',1)[1], v) for k, v in tot.items() if k.startswith("e_sortie_end:")), key=lambda x: -x[1])
    if deaths:
        print("  sortie end causes: " + ", ".join(f"{k} {v}" for k, v in deaths[:8]))

    errs = sorted(((k, v) for k, v in tot.items() if k.startswith("err_")), key=lambda x: -x[1])
    print(f"\n== Errors ({sum(v for _, v in errs)} total) ==")
    for k, v in errs[:15]:
        print(f"  {v:>6}  {'server' if k.startswith('err_s') else 'client'}  {k.split(':',1)[1]}")
    if not errs:
        print("  none")

if __name__ == "__main__":
    main()
