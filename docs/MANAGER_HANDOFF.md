# Manager handoff — Seraph Frame

Current state only (keep under ~80 lines). History goes to `docs/manager-log/<YYYY-MM>.md`.
Updated: 2026-10-27.

## State
- Repo made from the template; the 4 checks pass on `main`.
- `roblox.json` universe / place ids are empty (the owner fills them in). Needed before P8 teleports
  and any publish.
- Design is drafted (hub + area files 01–07, incl. mission zones). Name confirmed: Seraph Frame.
- Platforms: PC first, console later, no mobile. Story mode parked; Frames first.
- Prototypes P1–P8 planned in `docs/PROTOTYPES.md`. P1 (scale gym) started 2026-10-27.

## Sessions
| Session | Role | State |
|---|---|---|
| Manager | plans, merges, keeps this file | active |
| combat, seraphs, story, hq, art, tech | design drafting (01–06) | idle |
| mission-zones | drafted 07 (mission zones) | done |
| p1-scale-gym | builds P1 in its own worktree | starting |
| Studio test runner | owns Studio and the main desktop folder (`📺PORT:<port> Seraph Frame`) | starting |

## Branches
Each session updates its own row. Prototype branches are throwaway (not merged).

| Branch | Owner | Purpose | Head | State |
|---|---|---|---|---|
| `main` | manager | template + docs | — | green |
| `docs/manager-plan` | manager | this file + `PROTOTYPES.md` | — | PR open |
| `proto/p1-scale-gym` | p1-scale-gym | P1 scale gym (throwaway) | — | starting |

## Open items
1. P1: owner play-tests and signs off on 3.5 studs/m; then pick the next lanes (P2/P3/P4/P7/P8).
2. Owner decides on the optional `proto/p0-skeleton` step.
3. Mission zones 07: owner answers its open questions; it recommends a third place "Zone".
4. Fill `roblox.json` ids (numbers only).
