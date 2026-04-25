# Шаурма Тайкун (Shawerma Tycoon)

Original Roblox restaurant-management tycoon centered around a shawarma / street-food
fantasy. Built file-first with [Rojo](https://rojo.space/) — no work happens inside
Studio directly.

> Quality benchmark: Restaurant Tycoon 3 (RT3). We do **not** copy any RT3 assets,
> art, layouts, code, branding, or text — we recreate the depth and polish in an
> original way.

## Project layout

```
shawerma-tycoon/
├── default.project.json   # Rojo mapping (DataModel → src/)
├── docs/
│   └── REBUILD_PLAN.md    # Architecture, phases, rationale
└── src/
    ├── server/            # ServerScriptService.ShawermaTycoon
    │   ├── main.server.luau
    │   ├── Network/
    │   ├── Services/
    │   └── World/
    ├── client/            # StarterPlayer.StarterPlayerScripts.ShawermaTycoonClient
    │   ├── main.client.luau
    │   ├── Interaction/
    │   └── UI/
    └── shared/            # ReplicatedStorage.Shared (pure modules)
        ├── Constants.luau
        ├── DishCatalog.luau
        ├── Remotes.luau
        ├── Signal.luau
        ├── Types.luau
        └── Util.luau
```

## Local sync (Rojo)

1. Install [Rojo](https://rojo.space/docs/v7/getting-started/installation/) `>= 7.4`.
2. From the repo root: `rojo serve`.
3. In Roblox Studio install the Rojo plugin, click **Connect**, choose the running
   server, then **Sync In** for a fresh place.
4. Press Play. Phase 1 builds the starter restaurant programmatically and starts
   spawning customers — no manual world setup needed.

## Phase 1 — what's playable

- Programmatic starter restaurant: floor, walls, counter, kitchen, two tables, exit.
- Customer NPCs spawn → walk to counter → place a Shawarma order → wait.
- Player interacts with the cooking station (`E` proximity prompt) to **prep**, then
  **serve** the next customer in line.
- Customer pays + tips → walks to a free seat → eats → leaves. Seat auto-cleans.
- HUD shows money, queue length, and the current order status.
- Server-trusted economy (money is **never** mutated from the client).
- `DataService` persists money and unlocks via `DataStoreService` with `pcall`/retry
  and a versioned schema (safe migrations from v1 onward).

See [`docs/REBUILD_PLAN.md`](docs/REBUILD_PLAN.md) for the full plan, design
rationale, and roadmap for Phases 2–4.
