"""Daily "your pay is ready" notifications for AeroStrike.

Sends one Roblox experience notification to every player who played YESTERDAY (UTC) and
hasn't come back yet today. Roblox only delivers to players who opted in (the in-game
notification prompt) and allows at most one notification per player per day.

Setup (once, by the owner):
  1. Creator Dashboard > AeroStrike > Engagement > Notifications: create a notification string,
     e.g. "Your daily sortie pay is ready, {displayName}! Your streak is waiting." and copy its ID.
  2. Add "user-notifications: write" (scope user.user-notification:write) to the Open Cloud API key in .env.
  3. Put the ID in Tools/notify_config.json and set "enabled": true.

Run:   uv run --no-project python Tools/send_daily_notifications.py           (dry run unless enabled)
       uv run --no-project python Tools/send_daily_notifications.py --send    (really send)

Reads player lists from DataStore AS_Metrics keys u<day>_s<0-7> (written by MetricsServer).
The API key is read only inside this script and never printed.
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request, urllib.error

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

def request(key, method, url, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"x-api-key": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read().decode("utf-8")
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")[:300]

def users_for(key, day):
    out = set()
    for s in range(SHARDS):
        q = urllib.parse.urlencode({"datastoreName": STORE, "entryKey": f"u{day}_s{s}"})
        code, v = request(key, "GET", f"https://apis.roblox.com/datastores/v1/universes/{UNIVERSE}/standard-datastores/datastore/entries/entry?{q}")
        if code == 200 and isinstance(v, list):
            out.update(int(x) for x in v if isinstance(x, (int, float)))
        elif code not in (200, 404):
            sys.exit(f"DataStore read failed ({code}): {v}")
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--send", action="store_true", help="really send (otherwise dry run)")
    a = ap.parse_args()
    cfg = json.load(open(os.path.join(ROOT, "Tools", "notify_config.json"), encoding="utf-8"))
    key = api_key()
    if not key:
        sys.exit("No ROBLOX_API_KEY (.env or environment).")
    today = int(time.time() // 86400)
    yesterday, back = users_for(key, today - 1), users_for(key, today)
    targets = sorted(yesterday - back)
    print(f"played yesterday: {len(yesterday)}, already back today: {len(yesterday & back)}, to notify: {len(targets)}")
    live = a.send and cfg.get("enabled") and cfg.get("messageId")
    if not live:
        print("DRY RUN (pass --send, and set enabled + messageId in Tools/notify_config.json to send).")
        return
    sent = failed = 0
    for uid in targets:
        body = {
            "source": {"universe": f"universes/{UNIVERSE}"},
            "payload": {
                "type": "MOMENT",
                "messageId": cfg["messageId"],
                "joinExperience": {"launchData": "daily_pay"},
                "analyticsData": {"category": "Daily pay"},
            },
        }
        code, v = request(key, "POST", f"https://apis.roblox.com/cloud/v2/users/{uid}/notifications", body)
        if code == 200:
            sent += 1
        else:
            failed += 1
            if failed <= 3:
                print(f"  user {uid}: {code} {v}")
            if code in (401, 403):
                sys.exit("API key lacks user.user-notification:write (or the message ID is wrong).")
        time.sleep(0.15)
    print(f"sent {sent}, failed {failed} (players who never opted in are skipped by Roblox)")

if __name__ == "__main__":
    main()
