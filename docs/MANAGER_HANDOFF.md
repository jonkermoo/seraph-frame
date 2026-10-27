# Manager handoff — Seraph Frame

Current state only (keep under ~80 lines). History goes to `docs/manager-log/<YYYY-MM>.md`.
Updated: 2026-10-27.

## State
- Repo made from the template; the 4 checks pass on `main`.
- `roblox.json` universe / place ids are empty (the owner fills them in). Needed before P8 teleports
  and any publish.
- Design is drafted (hub + area files 01–06); mission zones (07) not drafted yet.
- Platforms: PC first, console later, no mobile. Story mode parked; Frames first.
- Next build step: prototypes P1–P8, planned in `docs/PROTOTYPES.md`. None started; waiting for the
  owner to pick.

## Sessions
| Session | Role | State |
|---|---|---|
| Manager | plans, merges, keeps this file | active |
| combat, seraphs, story, hq, art, tech | design drafting (01–06) | idle |
| mission-zones | drafts 07 (mission zones) | proposed, not started |
| Studio test runner | owns Studio (`📺PORT:<port> Seraph Frame`) | not started |

## Branches
Each session updates its own row. Prototype branches are throwaway (not merged).

| Branch | Owner | Purpose | Head | State |
|---|---|---|---|---|
| `main` | manager | template + docs | — | green |
| `docs/manager-plan` | manager | this file + `PROTOTYPES.md` | — | PR open |

## Open items
1. Owner picks which prototypes to start (P1 recommended first; then P2/P3/P4/P7/P8 in parallel).
2. Owner decides on the optional `proto/p0-skeleton` step.
3. Mission-zones design session: waiting for the owner to start it.
4. Fill `roblox.json` ids (numbers only).
5. Start a Studio test runner session before the first Studio test.
