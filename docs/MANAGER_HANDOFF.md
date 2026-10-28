# Manager handoff — Seraph Frame

Current state only (keep under ~80 lines). History goes to `docs/manager-log/<YYYY-MM>.md`.
Updated: 2026-10-27.

## State
- Repo made from the template; the 4 checks pass on `main`.
- `roblox.json` universe / place ids are empty (the owner fills them in). Needed before P8 teleports
  and any publish.
- Design is drafted (hub + area files 01–07, incl. mission zones). Name confirmed: Seraph Frame.
- Platforms: PC first, console later, no mobile. Story mode parked; Frames first.
- Prototypes P1–P8 planned in `docs/PROTOTYPES.md`. P1 done and signed off (3.5 studs/m) at `5325dab`.
- Pilots are custom R6 (no player avatars); Frame size is style, not power (see `DECISIONS.md`).

## Sessions
| Session | Role | State |
|---|---|---|
| Manager | plans, merges, keeps this file | active |
| combat, seraphs, story, hq, art, tech | design drafting (01–06) | idle |
| mission-zones | drafted 07 (mission zones) | done |
| p1-scale-gym | built P1 | done (signed off) |
| p2-frame-motor | builds P2 in its own worktree | waiting for Studio |
| model-tests | Frame skeleton v2 + 22 slots + placeholder pieces | waiting for owner's verdict |
| Studio test runner | owns Studio and the main desktop folder, Rojo port 34873 | idle |

## Branches
Each session updates its own row. Prototype branches are throwaway (not merged).

| Branch | Owner | Purpose | Head | State |
|---|---|---|---|---|
| `main` | manager | template + docs | — | green |
| `docs/manager-plan` | manager | this file + `PROTOTYPES.md` | — | PR open |
| `proto/p1-scale-gym` | p1-scale-gym | P1 scale gym (throwaway) | `5325dab` | done, not merged |
| `proto/p2-frame-motor` | p2-frame-motor | P2 Frame motor, cut from P1 (throwaway) | `d313c61` | waiting for Studio |
| `models/blender-tests` | model-tests | Frame rig data + Blender scripts | `599fa28` | pushed, verdict pending |

## Open items
1. P2 started 2026-10-27. Still open to start in parallel: P3/P4/P7/P8. Keep from P1 for M1:
   `Config/Scale`, `Config/Camera`, `Rules/FrameCam` + tests, R6 pilot built in code, exit from the
   client's final hull position.
2. Owner decides on the optional `proto/p0-skeleton` step.
3. Mission zones 07: owner answers its open questions; it recommends a third place "Zone".
4. Fill `roblox.json` ids (numbers only).
