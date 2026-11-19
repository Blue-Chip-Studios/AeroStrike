# AeroStrike launch plan (12-day ad window)

## Before you switch to Public (in this order)

1. **Publish the place** (Studio: File > Publish to Roblox). Every fix since the last publish is only in Studio until you do. That includes the tutorial, crash and rookie fixes, the badges and the gift ladder.
2. **Redo the Maturity & Compliance questionnaire.** It currently rates the game 13+. Arcade jets with explosions and no blood or gore is normally *mild violence* (9+). This decides whether under-13 players, a large share of Roblox, can see the game and your ads.
3. **Paste the title and description** from `Docs/StorePage.md`. The description is currently empty, and search matches on it.
4. **Turn off VR** (no VR controls) and **turn on automatic translation**.
5. **Buy each Robux item once on a live server** (Season Premium, Revive Here, one Cash Crate) to confirm the grants. Ask Roblox Support or use a test account if you want a refund.
6. **Play one session on a real phone.**
7. Switch to **Public**.

## The ads ($16/day x 12 days)

- Use **Roblox Ads Manager** (Sponsored / Search placements). Mobile-first targeting; ages 9+ once the rating is fixed.
- **Creatives:** start with the three thumbnails in `Assets/Marketing` as three ads in one campaign. After 2 days, move budget to the best click-through rate.
- **Keep the budget flat every day.** The algorithm reads consistency; don't front-load and stop.
- Expect roughly **100-300 visits/day from ads**. Ads alone won't reach 1,000 concurrent players. Their job is to give Roblox enough players to measure engagement. If engagement is strong, Roblox recommends the game (Home, Recommended, Up Next), and that's where real growth comes from.

## Live data

- **Ad campaign:** `c8314850-9c93-46b0-be6f-ce10bd8893cf` (Ads Manager; ad numbers have no API, so paste impressions / CTR / cost per visit from Ads Manager into the chat).
- **In-game metrics:** `MetricsServer` aggregates players, sessions, session length, new-player funnels, retention cohorts, Robux, devices and errors into the DataStore `AS_Metrics` every minute. Pull the report with:
  `uv run --no-project python Tools/metrics_report.py --days 7` (needs DataStore read on the API key in `.env`).

## What to watch every day (Creator Dashboard > Analytics)

| Metric | Healthy target | If it's low |
|---|---|---|
| Ad click-through rate | 2%+ | Swap to the best thumbnail; try the icon as the ad image |
| Onboarding funnel (ftue_*) | 70%+ reach `go_live` | Find the step with the biggest drop and tell me which one |
| Average session length | 10+ min | Check the session funnel (session_*). If players leave before `first_kill`, combat is too hard or too slow |
| D1 retention | 15%+ (great: 25%+) | Daily reward, codes and notifications. Post a new code mid-week |
| Payer conversion | 1-3% | Check which shop item is viewed but not bought (shop_* funnel) |
| Crashes / errors | ~0 | Send me the Developer Console errors |

## Mid-window boosts (days 4-8)

- **Day 4:** release code `SKYFIRE` (500 cash). Add it to `Config/SeasonConfig.luau` and publish. Post it in the description. New codes bring players back.
- **Day 6:** run a weekend **double cash** event if retention is good (I can add a timed multiplier).
- **Badges:** the scheduled task creates the remaining 9 over the next two days. Publish after each batch.

## What's already done (scorecard)

| Area | Status |
|---|---|
| Instant action | Airborne within ~5 s of joining |
| Tutorial | Guns step 7 s (was 44 s); finished 10-23 s after launch; no dead ends |
| Early survival | Rookie protection for ranks 1-5; hitbox "crashes" fixed (were half of rookie deaths) |
| Early rewards | +7,000 cash in the first 3.5 minutes; first jet affordable in session 1 |
| Session length | Gift ladder 3/7/12/20/30 min (AFK-proof), challenges, Fortress boss every 9 min |
| Coming back | Daily streak, season track, codes, favourite + notification prompts, Top Aces boards |
| Content | 5 jets, mastery paints for every jet, season trails, 3 mission types, boss event |
| Mobile / tablet | Phone and tablet layouts checked; text floor; Stick steering option |
| Store | Icon + 3 thumbnails live; 5 badges live (9 more scheduled); passes and products live |
| Performance | ~0.5 ms server scripts with 8 players; client stable at 60 fps |
| Analytics | Onboarding, session and shop funnels plus economy and custom events |

**Still open (yours):** age-rating questionnaire, description, VR off, translation, publish, real-device test, live purchase check.
