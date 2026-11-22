"""Daily "come back" notifications for AeroStrike.

Sends one Roblox experience notification to every player who played YESTERDAY (UTC) and hasn't
come back yet today. Roblox only delivers to players who opted in (the in-game notification
prompt) and allows at most one notification per player per day.

Per player (from the record MetricsServer saves when they leave: daily streak + last claim day):
  - claimed their daily pay yesterday -> streak still alive -> "streak" template ({days} = streak)
  - otherwise                         -> "daily" template ({day}, {cash} = their next pay), if set up
Templates and their parameters live in Tools/notify_config.json (message IDs from
Creator Dashboard > Engagement > Notifications).

Setup: add "user-notifications: write" (scope user.user-notification:write) to the Open Cloud API
key in .env, set "enabled": true in notify_config.json.

Run:   uv run --no-project python Tools/send_daily_notifications.py                 (dry run)
       uv run --no-project python Tools/send_daily_notifications.py --send          (send to everyone eligible)
       uv run --no-project python Tools/send_daily_notifications.py --send --only <userId>   (test one player)

The API key is read only inside this script and never printed.
"""
import argparse, json, os, re, sys, time, urllib.parse, urllib.request, urllib.error

UNIVERSE = 10777495043
STORE = "AS_Metrics"
SHARDS = 8
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def api_key():
    if os.environ.get("ROBLOX_API_KEY"):
        return os.environ["ROBLOX_API_KEY"]
    path = os.path.join(ROOT, ".env")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line.startswith("ROBLOX_API_KEY"):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None

def daily_track():
    src = open(os.path.join(ROOT, "Config", "EconomyConfig.luau"), encoding="utf-8").read()
    m = re.search(r"DailyTrack\s*=\s*\{([^}]*)\}", src)
    return [int(x) for x in re.findall(r"\d+", m.group(1))] if m else [100]

def request(key, method, url, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"x-api-key": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read().decode("utf-8")
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")[:300]

def players_for(key, day):
    """{userId: {"s": streak, "l": lastClaimDay}} (old plain-id entries get an unknown streak)."""
    out = {}
    for s in range(SHARDS):
        q = urllib.parse.urlencode({"datastoreName": STORE, "entryKey": f"u{day}_s{s}"})
        code, v = request(key, "GET", f"https://apis.roblox.com/datastores/v1/universes/{UNIVERSE}/standard-datastores/datastore/entries/entry?{q}")
        if code == 200 and isinstance(v, list):
            for e in v:
                if isinstance(e, dict) and "i" in e:
                    out[int(e["i"])] = {"s": int(e.get("s") or 0), "l": int(e.get("l") or 0)}
                elif isinstance(e, (int, float)):
                    out.setdefault(int(e), {"s": 0, "l": 0})
        elif code not in (200, 404):
            sys.exit(f"DataStore read failed ({code}): {v}")
    return out

def plan_for(rec, yesterday, track):
    """Which template and values for this player tomorrow (= today)."""
    alive = rec["l"] == yesterday and rec["s"] > 0  # claimed yesterday: streak continues if they claim today
    streak = rec["s"] if alive else 0
    day = (streak % len(track)) + 1
    return ("streak" if alive else "daily"), {"streak": str(streak), "day": str(day), "cash": str(track[day - 1])}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--send", action="store_true", help="really send (otherwise dry run)")
    ap.add_argument("--only", type=int, help="send only to this userId (testing)")
    a = ap.parse_args()
    cfg = json.load(open(os.path.join(ROOT, "Tools", "notify_config.json"), encoding="utf-8"))
    key = api_key()
    if not key:
        sys.exit("No ROBLOX_API_KEY (.env or environment).")
    track = daily_track()
    today = int(time.time() // 86400)
    yday = players_for(key, today - 1)
    back = players_for(key, today)
    targets = {uid: rec for uid, rec in yday.items() if uid not in back}
    if a.only:
        targets = {a.only: yday.get(a.only) or back.get(a.only) or {"s": 1, "l": today - 1}}
    plans = {}
    for uid, rec in targets.items():
        kind, vals = plan_for(rec, today - 1, track)
        tpl = cfg.get(kind) or {}
        if not tpl.get("messageId"):
            continue  # template not set up yet
        plans[uid] = (kind, tpl, vals)
    by_kind = {}
    for kind, _, _ in plans.values():
        by_kind[kind] = by_kind.get(kind, 0) + 1
    print(f"played yesterday: {len(yday)}, already back today: {len(set(yday) & set(back))}, eligible: {len(targets)}, "
          f"sendable now: {len(plans)} {by_kind} (templates without a messageId are skipped)")
    if not (a.send and cfg.get("enabled")):
        print("DRY RUN (needs --send and \"enabled\": true in Tools/notify_config.json).")
        return
    sent = failed = skipped = throttled = 0
    for uid, (kind, tpl, vals) in plans.items():
        params = {name: {"stringValue": vals[field]} for name, field in (tpl.get("params") or {}).items()}
        body = {
            "source": {"universe": f"universes/{UNIVERSE}"},
            "payload": {
                "type": "MOMENT",
                "messageId": tpl["messageId"],
                "parameters": params,
                "joinExperience": {"launchData": f"notify_{kind}"},
                "analyticsData": {"category": "Daily streak" if kind == "streak" else "Daily pay"},
            },
        }
        code, v = request(key, "POST", f"https://apis.roblox.com/cloud/v2/users/{uid}/notifications", body)
        if code == 200:
            sent += 1
        elif code == 400 and "not opted in" in str(v):
            skipped += 1  # normal: only players who accepted the in-game prompt can receive them
        elif code == 429 or "throttl" in str(v).lower():
            throttled += 1  # Roblox's one-per-day limit / rate limit
        else:
            failed += 1
            if failed <= 3:
                print(f"  user {uid}: {code} {v}")
            if code in (401, 403):
                sys.exit("API key lacks user.user-notification:write (or a message ID is wrong).")
            if code == 400 and failed >= 3 and sent == 0:
                sys.exit("Stopping: the request format was rejected 3 times (see above).")
        time.sleep(0.15)
    print(f"sent {sent}, not opted in {skipped}, throttled {throttled}, failed {failed}")

if __name__ == "__main__":
    main()
