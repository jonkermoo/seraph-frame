# Prototypes P1–P8 (M0)

Plan for the eight throwaway prototypes that come before the M1 vertical slice. Each answers one
technical risk. **PC only**: budgets are the PC column (mid GPU, 60 fps); there are no mobile budgets or
phone checks. Console comes later, so every input goes through `ContextActionService` with a gamepad
binding next to the keyboard/mouse one, and cameras must work on a stick.

Status: **planned, nothing started.** The user picks which to start.

## Shared rules for every prototype
- One branch per prototype, cut from `main`: `proto/pN-<name>`. Throwaway: the branch is not merged.
  What survives (Config numbers, pure `Rules/` modules with Lune tests, a decision in `DECISIONS.md`)
  goes into M1 on a fresh branch.
- Numbers in `src/shared/Config/<Area>.luau`, remotes in `src/shared/Net.luau`, pure logic in
  `src/shared/Rules/` with tests in `tests/run.luau`. The 4 checks pass before Studio sees it.
- Map size is v1's 3 × 3 km = **10,500 × 10,500 studs** (3.5 studs/m), centred on the origin.
- Studio is shared and serial: code can be written in parallel, but Studio tests run one at a time.
- Each prototype ends with a short result note (numbers measured, pass/fail, what to keep).

## Per-prototype plan

| P | Branch | Goal (risk it answers) | Studio? |
|---|---|---|---|
| P1 | `proto/p1-scale-gym` | Scale and cameras feel right (motion sickness, scale) | yes, user sign-off |
| P2 | `proto/p2-frame-motor` | Client-owned 140-stud hull replicates cleanly (Frame feel) | yes, 2 clients |
| P3 | `proto/p3-destruction` | Pre-fractured buildings + chunk pool stay cheap | yes, perf |
| P4 | `proto/p4-streaming-city` | 10.5k-stud city from layout data streams without pop-in | yes, perf |
| P5 | `proto/p5-anim-scale` | Animation at 28× scale, upload pipeline end to end | yes |
| P6 | `proto/p6-load-test` | Server holds 12 hulls + 3 Seraphs + breaks | yes, server stats |
| P7 | `proto/p7-cel-look` | Outline/cel look within tri budget | yes, user sign-off |
| P8 | `proto/p8-save-teleport` | Saves survive teleports and Studio stops | yes, published places |

### P1 — Scale gym
- **Build**: pilot (R6), 140-stud Frame block-out, 300-stud Seraph block-out, 4 buildings, first- and
  third-person Frame cameras, pilot camera. Gamepad: both cameras on the right stick, sensitivity in Config.
- **Files**: `src/shared/Config/Scale.luau`, `Config/Camera.luau`; `src/client/Frame/Camera.luau`,
  `src/client/Frame/Controller.luau` (block-out walk only); `src/server/Services/Gym.luau` (spawns block-outs).
- **Pass**: it feels huge; the camera never clips into buildings or the hull; no nausea in a 5-min first-
  person walk (motion slider works); **user signs off on 3.5 studs/m**.
- **Parallel**: none needed first; everything after uses its scale numbers. Start P1 first.

### P2 — Frame motor
- **Build**: hull assembly (no Humanoid) + `FrameMotor` (dash, leap, stop) on the client, `FrameGuard`
  motion envelope on the server, 2 clients. Keyboard and gamepad bindings.
- **Files**: `src/shared/Rules/FrameMotor.luau`, `Config/Frame.luau`; `src/client/Frame/Controller.luau`;
  `src/server/Services/Frame.luau`, `Services/FrameGuard.luau`; `Net.luau` (frame intents); tests for
  the motor and the guard envelope.
- **Pass**: no jitter for watchers at 150 ms simulated ping; network ownership never flips on bumps;
  zero false FrameGuard strikes in a 10-min session; motor rules tested in Lune.
- **Parallel**: with P3, P4, P7, P8 (after P1's scale numbers).

### P3 — Destruction stress
- **Build**: 200 kit buildings, scripted breaks at 5/s, chunk pool with timed reset and a shared budget.
- **Files**: `src/shared/Config/City.luau`, `Config/Perf.luau`; `src/client/City/Debris.luau`;
  `src/server/Services/City.luau` (building hp, break events); `Net.luau` (break event);
  `tools/` (Blender fracture script) and kit meshes in `assets/` (logged in `ASSETS_LICENSES.md`).
- **Pass**: PC ≥ 60 fps (≤ 16 ms) with 1,500 live chunks; server break-event cost negligible
  (< 0.5 ms per break); pool never leaks (chunk count returns to baseline after reset).
- **Parallel**: with P2, P4, P7, P8.

### P4 — Streaming + city generation
- **Build**: full 10.5k layout generated from plain data, StreamingMesh LOD, Atmosphere haze, sprint
  a Frame across the map.
- **Files**: `src/shared/City/Layout.luau`, `City/Districts.luau` (plain data, Lune-tested);
  `src/server/Services/City.luau` (build from data); `Config/City.luau` (streaming radii);
  `default.project.json` (Workspace streaming properties); `tools/` (layout preview).
- **Pass**: city builds in < 3 s; client memory ≤ 2 GB; ≤ 25k streamed parts near the camera; skyline
  visible at all times; no fall-through at full Frame sprint; layout data tested in Lune.
- **Parallel**: with P2, P3, P7, P8. Shares `Services/City.luau` and `Config/City.luau` with P3:
  if both run, they are trial-merged before results are kept.

### P5 — Animation at scale
- **Build**: one rigid Frame rig, walk / sprint / dash clips authored at full scale, IK feet.
- **Files**: `src/client/Frame/View.luau` (rig build + anim + IK); `Config/Frame.luau` (anim speeds);
  `tools/` (animation export); asset ids in `ASSETS_LICENSES.md`.
- **Pass**: no foot skating at walk, sprint or dash; the upload pipeline (author → KeyframeSequence →
  upload → play) works end to end.
- **Parallel**: after P1 (needs the signed-off scale) and best after P2 (drives the rig from the motor).

### P6 — Load test
- **Build**: 12 server-driven bot hulls + 3 Seraph stubs (server brains at 10–15 Hz) + building breaks.
- **Files**: `src/server/Services/LoadBots.luau` (prototype only), `Services/Seraph.luau`,
  `src/shared/Rules/Seraph/Stub.luau`, `Config/Perf.luau`; reuses P2's hull and P3's breaks.
- **Pass**: server Heartbeat ≥ 55 Hz; Seraph ticks ≤ 2 ms; FrameGuard ≤ 0.5 ms; ≤ 40 KB/s out per player
  steady. If there is headroom, note whether 16 players would fit.
- **Parallel**: no. Runs after P2 and P3 (merges their branches into its own).

### P7 — Outline / cel look
- **Build**: inverted-hull outlines baked in Blender on a Frame, a Seraph and one district block;
  `Highlight` only on targets.
- **Files**: `tools/` (Blender outline bake); `src/client/Vfx/Outline.luau`; `Config/Perf.luau`
  (Highlight cap, quality levels); `src/shared/Art/Palette.luau`; meshes logged in `ASSETS_LICENSES.md`.
- **Pass**: the user approves the look; own Frame ≤ 60k tris and ≤ 30 parts; Seraph LOD0 ≤ 80k tris;
  meshes under 20k tris each.
- **Parallel**: with everything (mostly art and Blender work).

### P8 — Save + teleport
- **Build**: ProfileStore with a versioned schema and session locking; Kurogane → test place → back;
  idempotent reward grant; party list through MemoryStore, never teleport data.
- **Files**: `src/shared/Data/Defaults.luau`, `Data/Schema.luau`, `Data/Migrations.luau` (Lune-tested);
  `src/server/Services/Profile.luau`, `Services/Teleport.luau`; `wally.toml` (ProfileStore);
  `kurogane.project.json`, `episode.project.json`.
- **Pass**: no lost writes in 20 join/leave/teleport cycles; locks released before teleport; a Studio stop
  mid-save loses nothing; the `loadFailed` path kicks cleanly; migrations tested in Lune.
- **Needs**: universe and place ids in `roblox.json` and a published test game (teleports do not run in
  Studio). Until the ids exist, only the save half can be tested.
- **Parallel**: with everything; no shared files except `Net.luau` and `tests/run.luau`.

## Order and parallel lanes
1. **P1 first** (sets the scale for everything else).
2. Then up to four lanes at once: **P2**, **P3** or **P4**, **P7**, **P8**.
3. **P5** after P1 (better after P2). **P6** last, after P2 and P3.

Shared files every branch touches: `src/shared/Net.luau`, `tests/run.luau`, `src/server/init.server.luau`,
`src/client/init.client.luau`. These conflict append-only on merge; since prototypes are not merged,
it only matters for P6 (and P3 + P4 if both are kept).

## Optional step 0 (recommended, not started)
A tiny `proto/p0-skeleton` branch merged to `main` before P1: the `Bootstrap` + `Services/` folder layout
from the tech design §8, `Config/Scale.luau`, and a gamepad input map. It makes every prototype start from
the same layout and cuts the merge conflicts above. Only on the user's yes.
