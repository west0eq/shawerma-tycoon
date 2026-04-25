# Шаурма Тайкун — Rebuild Plan

## 1. Audit summary

There was no pre-existing `shawerma/` project in any of the connected
repositories, so this repo is a **clean-slate rebuild** rather than a refactor.
The bar set by the brief is treated as the starting point: the previous
prototype (referenced in the request) is assumed to be structurally weak and is
not carried over. We start with a deliberately small but production-quality
vertical slice and grow it phase by phase.

What is intentionally **not** here yet (and why):

| Missing                      | Reason                                                |
|------------------------------|-------------------------------------------------------|
| Staff (cook/server/cleaner)  | Phase 3 — needs a stable customer loop first.         |
| Decor + atmosphere modifiers | Phase 3.                                              |
| Atmosphere & food-quality axis of rating | Phase 3 — service axis is wired in P2.    |
| Multiplayer plot isolation   | Phase 4 — single-host plot in P2.                     |

Phase 2 status (this branch) ships:

* **Build mode foundation** — grid-snap placement, rotation (R/Q), remove,
  sell, ghost preview, server validation (bounds + AABB overlap + inventory
  check), persistence in `PlayerSave.placed`.
* **Menu expansion** — 9 dishes across 5 categories (wrap / plate / side /
  drink / dessert) with declarative unlock requirements.
* **Multi-station cooking pipeline** — `StationService` registers any number
  of stations (built-in + player-placed). Orders route by category.
* **Service-axis rating** — sliding-window scoring with `customer_left_angry`
  and `served_fast` events feeding into a 1–5 star score.
* **Shop / Inventory / Build UI** — sidebar + modal panels.

## 2. Gameplay pillars

1. **Restaurant fantasy first.** Every system answers "does this make the player
   feel like they're running a real shawarma joint that's getting better?"
2. **Readable progression.** The player should always know exactly what to do
   next — the next upgrade, the next unlock, the next milestone.
3. **Satisfying short loop.** Cook → serve → tip → clean → repeat must feel
   tactile inside ten seconds, before any meta-progression kicks in.
4. **Automation as a reward.** Staff replace the player's hand actions, never
   replace the player's strategic decisions.
5. **Original identity.** Shawarma is the flagship, and the visual / audio /
   tone language is built around street-food culture, not restaurants in
   general. RT3 is the *quality* benchmark, not a template.

## 3. Architecture

```
ReplicatedStorage.Shared        (pure modules, safe for both contexts)
├── Constants                   single source of truth for tunables
├── DishCatalog                 data-driven dish definitions
├── BuildCatalog                placeable item definitions + factories
├── Remotes                     creates / fetches the Remotes folder
├── Signal                      tiny BindableEvent-backed signal
├── Types                       Luau type aliases
└── Util                        formatMoney, lerp, weighted random, …

ServerScriptService.ShawermaTycoon
├── main.server                 bootstrap (build world → start services)
├── Network.RemotesInit         declares every RemoteEvent / RemoteFunction
├── World.RestaurantBuilder     procedural starter restaurant
├── Services
│   ├── DataService             DataStore wrapper, versionable schema
│   ├── EconomyService          money/income/expense, server-trusted
│   ├── OrderService            pending-order queue + state machine
│   ├── StationService          multi-station cooking pipeline
│   ├── InventoryService        owned-but-not-placed item counts
│   ├── ShopService             RequestBuy → debit + add to inventory
│   ├── BuildService            place / remove / sell with persistence
│   ├── CustomerService         spawn, queue, order, seat, eat, leave
│   └── RatingService           service-axis sliding-window star rating
└── ...

StarterPlayerScripts.ShawermaTycoonClient
├── main.client                 wires everything on the client
├── UI.Theme                    shared visual tokens
├── UI.HUD                      money / queue / station status
├── UI.Notifications            transient toast messages
├── UI.Sidebar                  Shop / Build buttons
├── UI.ShopPanel                browse + buy items
├── UI.BuildPanel               browse inventory + remove placed items
└── BuildMode.Controller        ghost preview + placement input
```

Cross-cutting principles:

- **Server is authoritative.** Money, unlocks, order completion, ratings, and
  customer state all live on the server. Remotes only carry intent ("I want to
  prep") and confirmation ("you served customer #42").
- **No deep coupling.** Services expose narrow, intentional APIs and
  communicate via the shared `Signal` module. Adding a fourth service tomorrow
  shouldn't require editing the other three.
- **Data is data, not code.** Dish properties, prices, prep times, customer
  patience, and economic constants all live in `Shared.Constants` /
  `Shared.DishCatalog`, never sprinkled across logic files.
- **Migrations from day one.** `DataService` records a schema version on every
  save and applies migrations on load — Phase 2 won't break Phase 1 saves.

## 4. Implementation phases

### Phase 1 — Playable starter loop ✅ (this PR)
- Clean Rojo layout, zero script errors on sync.
- Procedural starter restaurant (no Studio assets required).
- Customer state machine: `Spawning → Walking → Queueing → Ordering → Waiting →
  Eating → Leaving`.
- Cooking state machine on station: `Idle → Prepping → Ready → Served`.
- Money + tips flow end-to-end, persisted via `DataService`.
- HUD: cash, queue length, current order status.

### Phase 2 — Build mode + service polish
- Grid-snapped placement, rotation, move, store, sell, ghost preview, validation.
- Inventory panel + shop panel.
- Menu expansion: wraps, plates, drinks, sides — each with prep stations.
- Customer satisfaction signals (wait time, food quality) start being recorded.

### Phase 3 — Staff, rating, atmosphere
- Hire / upgrade cook, cashier, server, cleaner, prep worker.
- Rating system: stars, service score, food score, atmosphere score.
- Decor / atmosphere modifiers feeding back into spawn rate + tips.
- Restaurant-level upgrades (capacity, payment speed, prep speed, marketing).

### Phase 4 — Polish, balance, content
- Economy tuning, save robustness (reconnect, partial-failure handling).
- More dishes, more decor, more milestone tracks.
- Performance pass (NPC scaling, event-driven ticks, no per-frame scans).
- Anti-exploit hardening pass.

## 5. Risks and blockers

| Risk                                       | Mitigation                                                       |
|--------------------------------------------|------------------------------------------------------------------|
| NPC pathing deadlocks                      | Single-lane queue + per-customer state machine, no pathfinding race conditions in P1. |
| DataStore failures / throttling            | `pcall` + bounded retry + in-memory fallback; saves on session-end and on milestone ticks, not every transaction. |
| Build mode complexity blowing up scope     | Phase 2 is a separate slice; not gated on P1 customers/cooking. |
| Visual fidelity without external assets    | Procedural geometry in P1; art pass scheduled inside Phase 4.    |
| Anti-exploit gaps                          | All economy mutations server-side; client only ever sends *intent*. |

## 6. Testing checklist (Phase 1)

- [ ] `rojo serve` then Studio **Connect → Sync In** produces zero output errors.
- [ ] Press Play: starter restaurant builds; HUD shows starting cash.
- [ ] First customer spawns within ~10 s, walks to the counter, places an order.
- [ ] Standing on the cooking station shows an `E — Prep Shawarma` prompt.
- [ ] Holding `E` runs the prep timer, then prompt becomes `E — Serve`.
- [ ] Serving pays you base price + a small tip; HUD updates immediately.
- [ ] Customer walks to a free seat, eats, then walks to the exit and despawns.
- [ ] Seat auto-cleans and accepts the next customer.
- [ ] Leaving and rejoining preserves your money (DataStore round-trip).
- [ ] Spamming remotes from the client cannot mutate money.
