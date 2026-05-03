# Scripting Task List: Kang Parkir

All scripts written in Luau. Framework: **Knit** (client/server separation).
File paths are relative to `src/` under the Rojo project root.

---

## Legend

- [ ] = Not started
- [x] = Done
- Priority: **P1** = Blocking (first playtest) | **P2** = Core feature | **P3** = Polish/optional

---

## 1. Project Bootstrap & Framework

- [ ] **P1** `src/shared/Knit.lua` — install and configure Knit framework
- [ ] **P1** `src/server/init.server.lua` — boot Knit services on server
- [ ] **P1** `src/client/init.client.lua` — boot Knit controllers on client
- [ ] **P1** `src/shared/Constants.lua` — all tunable values (radii, speeds, durations, costs, payout multipliers, spawn weights). Single source of truth.
- [ ] **P1** `src/shared/Types.lua` — shared type definitions (PlayerData, VehicleState, EventType, etc.)
- [ ] **P1** `src/shared/Enums.lua` — state enums (VehicleState, PlayerState, EventType, NPCState)

---

## 2. Data Persistence

- [ ] **P1** `src/server/services/DataService.lua` — wraps `ProfileService`
  - Load player profile on join
  - Save on leave and periodic auto-save (every 60s)
  - Schema: `{ BankedEarnings, SkillTree, OwnedCosmetics, OwnedGamepasses, TotalSessions, Stats }`
  - Version field for future migrations
- [ ] **P1** `src/server/services/DataService.lua` — expose `GetProfile(player)`, `AddBankedEarnings(player, amount)`, `DeductBankedEarnings(player, amount)`
- [ ] **P2** `src/server/services/DataService.lua` — `GetLeaderboardTop10()` (BankedEarnings global sort, cached, refreshed every 5 min)

---

## 3. Session & Zone Management

- [ ] **P1** `src/server/services/SessionService.lua` — manages session lifecycle
  - States: `Lobby → WarmUp → PeakShift → RushHour → ShiftEnd → PostSession`
  - Timer ticks broadcast via `UnreliableRemoteEvent` to all clients
  - Fires phase-change events consumed by other services
- [ ] **P1** `src/server/services/ZoneService.lua` — assigns parking lot zones to players on join
  - First-come, first-served zone allocation
  - Zone size recalculation when player count changes
  - Owns `IsInZone(player, position)` and `GetZoneOwner(zone)` queries
  - Overflow zone fallback logic
- [ ] **P1** `src/server/services/ZoneService.lua` — trespassing enforcement: auto-eject foreign vehicles after 5s

---

## 4. Traffic & Spawn System

- [ ] **P1** `src/server/services/TrafficService.lua` — vehicle spawn loop
  - Reads `Constants.SpawnWeights` table for vehicle type probability
  - Spawns vehicles at traffic spawn node at configurable interval
  - Assigns each vehicle a unique `VehicleId`
  - Enforces max simultaneous vehicle cap per server
- [ ] **P1** `src/server/services/TrafficService.lua` — vehicle despawn logic
  - Vehicles on default traffic path that reach despawn node are destroyed
  - Vehicles idling at lot entrance > 15s return to traffic path
- [ ] **P2** `src/server/services/TrafficService.lua` — Flash Mob override mode
  - Temporarily sets spawn weight to 95% Scooter for 10 seconds
  - Re-injects 30+ vehicles in burst
- [ ] **P1** `src/server/services/VehicleService.lua` — per-vehicle state machine
  - States: `Traffic → Aggroed → AtEntrance → Dragging → Parked → Damaged → Departing`
  - Owns pathfinding target updates via `PathfindingService`
  - Exposes `SetAggro(vehicleId, player)`, `ClearAggro(vehicleId)`, `SetParked(vehicleId, player, position)`, `SetDamaged(vehicleId)`, `GetState(vehicleId)`

---

## 5. Whistle System

- [ ] **P1** `src/server/services/WhistleService.lua`
  - Receives `WhistleStart` / `WhistleStop` `RemoteEvent` from client
  - Rate limit: max 1 activation per 0.5s per player
  - Runs spherical `OverlapParams` query at player position with radius = `BaseRadius + WhistleStat × Scale`
  - Calls `VehicleService:SetAggro()` for each valid vehicle found
  - Triggers `TugOfWarService` when two players contest same vehicle
- [ ] **P1** `src/server/services/TugOfWarService.lua`
  - Initiates tug-of-war state for a contested vehicle
  - Listens for APM input events from both players via `RemoteEvent` for 1.5 seconds
  - Tallies input score per player
  - Calls `VehicleService:SetAggro()` for winner
  - Applies 0.5s whistle cooldown to loser
  - Fires `TugOfWarResult` event to both clients for UI update
- [ ] **P1** `src/client/controllers/WhistleController.lua`
  - Handles whistle input (hold/release)
  - Drains stamina locally (visual only; server is authoritative)
  - Fires `WhistleStart` / `WhistleStop` `RemoteEvent`
  - Plays whistle SFX at assigned pitch
  - Triggers whistle VFX on local character

---

## 6. Vehicle Drag (Street Tetris)

- [ ] **P1** `src/server/services/DragService.lua`
  - Receives `DragStart(vehicleId)` from client
  - Validates: vehicle at entrance, player owns zone, vehicle not already dragged
  - Unanchors vehicle assembly
  - Creates `AlignPosition` + `AlignOrientation` constraints between vehicle `PrimaryPart` and player `HumanoidRootPart`
  - Sets vehicle `CollisionGroup` to ignore player but collide with other vehicles
  - Receives `DragConfirm(vehicleId, position, orientation)` from client
  - Validates: position within zone bounds
  - Removes constraints, re-anchors vehicle at confirmed position/orientation
  - Runs `AlignmentBonus` calculation (DotProduct of LookVectors vs. adjacent vehicles)
  - Calls `EconomyService:AddPayout(player, payout)`
- [ ] **P1** `src/server/services/DragService.lua` — tip-over detection
  - Server monitors angular velocity of active dragged assemblies each heartbeat
  - If `AngularVelocity.Magnitude > TipThreshold`: fires penalty, detaches constraints, runs domino check
  - Domino check: `OverlapParams` sphere (1.5 stud radius) from tip-over point, applies impulse to adjacent anchored vehicles
- [ ] **P1** `src/client/controllers/DragController.lua`
  - Handles interact input near a vehicle at entrance
  - Fires `DragStart` to server
  - Receives server confirmation, enters drag visual mode
  - Shows spatial grid overlay on local terrain
  - Sends updated drag position to server via `UnreliableRemoteEvent` (high frequency, visual interpolation)
  - Fires `DragConfirm` on release
- [ ] **P2** `src/client/controllers/DragController.lua` — VIP Supercar QTE
  - On `DragConfirm` for Supercar: triggers a local QTE mini-game (timed button sequence)
  - Reports QTE result to server via `RemoteEvent`
  - Server applies full or 50% payout based on result

---

## 7. PvP Combat

- [ ] **P1** `src/server/services/CombatService.lua` — Tackle (Dash)
  - Receives `DashRequest(direction)` from client
  - Validates: stamina ≥ dash cost, cooldown clear, direction within 45° of character facing
  - Applies `VectorForce` impulse to player `HumanoidRootPart`
  - During 0.3s window: runs `OverlapParams` box hit detection at player position each heartbeat
  - On hit: sets target `Humanoid.PlatformStand = true` for 1.5s, detaches any active drag constraints on target
- [ ] **P1** `src/server/services/CombatService.lua` — Melee Strike
  - Receives `StrikeRequest` from client
  - Fires `OverlapParams` box (3×2 studs) in front of player
  - Hit priority: Helmet Thief NPC > Rival Player > (nothing else)
  - On NPC Thief hit: calls `ThiefService:Interrupt(thiefId)`
  - On Rival Player hit: applies small knockback impulse, cancels target's active action (drag/whistle)
- [ ] **P1** `src/client/controllers/CombatController.lua`
  - Handles Dash and Strike inputs
  - Deducts stamina locally (visual)
  - Fires `DashRequest` / `StrikeRequest` to server
  - Plays dash animation and trail VFX locally
- [ ] **P2** `src/server/services/CombatService.lua` — Spike Strip
  - Receives `PlaceStrip(position)` from client
  - Validates: player owns a strip consumable, position within 5 studs of player, ground surface valid
  - Spawns Spike Strip `Part` on server, tagged with player ID
  - Binds `Touched` event: on NPC vehicle `PrimaryPart` contact → `VehicleService:SetDamaged()`, voids payout, destroys strip
  - Rival player strike on strip: destroys strip (1 hit)

---

## 8. Economy System

- [ ] **P1** `src/server/services/EconomyService.lua`
  - `AddPayout(player, amount)` — adds to unbanked shift currency, fires UI update event
  - `ApplyPenalty(player, amount)` — deducts from unbanked shift currency (floor: 0)
  - `BankEarnings(player)` — transfers unbanked → banked in DataService, must be called when player reaches Bank Terminal
  - `SpendShiftCurrency(player, amount)` — deducts unbanked for in-match purchases; returns `success: boolean`
  - `GetUnbanked(player)` — returns current unbanked amount
- [ ] **P1** `src/server/services/EconomyService.lua` — payout formula
  - `CalculatePayout(vehicleType, alignmentBonus, eventMultiplier, penalties)` → number
- [ ] **P2** `src/server/services/EconomyService.lua` — end-of-session auto-bank
  - At `ShiftEnd` phase: all remaining unbanked currency is banked automatically
  - (Raid penalty only applies during active Raid event, not at shift end)

---

## 9. Helmet Thief AI

- [ ] **P1** `src/server/services/ThiefService.lua` — spawn manager
  - Max 2 thieves alive simultaneously
  - Respawn delay 45–90s after despawn
  - Priority target: Sport Bikes with helmets in any player's lot
- [ ] **P1** `src/server/services/ThiefService.lua` — Behavior Tree runner
  - Implemented as a coroutine-based state machine (no external BT library required)
  - States: `Roam → Navigate → Interact → Flee → Ragdoll → Despawn`
  - `Interact` state: 3s countdown, plays rummage animation on NPC rig, then un-welds helmet
  - `Flee` state: pathfinds to despawn node; helmet asset moves with NPC as a weld
  - On reaching despawn node: helmet and thief destroyed; fires `HelmetStolen` event to owning player
- [ ] **P1** `src/server/services/ThiefService.lua` — `Interrupt(thiefId)`
  - Cancels active Sequence node
  - Drops helmet as unanchored `Part` at current thief position
  - Sets thief to `Ragdoll` state (enables `Humanoid.PlatformStand`, applies physics) for 1s
  - After 1s: resumes `Roam` state, 10s cooldown on re-targeting
- [ ] **P2** `src/server/services/ThiefService.lua` — player notification
  - On thief entering a player's zone: fires `UnreliableRemoteEvent` to that player to show threat HUD arrow

---

## 10. Police AI (Satpol PP)

- [ ] **P2** `src/server/services/PoliceService.lua` — spawn/despawn
  - Spawns 2–4 police NPCs at map edge nodes when Raid event fires
  - Despawns all when event ends
- [ ] **P2** `src/server/services/PoliceService.lua` — pursuit logic
  - Each police NPC targets nearest player not inside a `HidingVolume`
  - LoS raycast check: if player is behind a `HidingVolume` part, raycast is blocked → not targeted
  - If within 3 studs of target for 2 continuous seconds: fires `Caught` on that player
    - `EconomyService:ApplyPenalty(player, unbanked × 0.20)`
    - Teleport player to Citation position
    - Apply 3s stun (lock inputs)
  - Bribe Money consumable: clears this NPC's targeting on the using player for remainder of event

---

## 11. Dynamic Event System

- [ ] **P1** `src/server/services/EventService.lua` — `EventController`
  - Random timer: fires one event every 180–420 seconds (3–7 min)
  - Only one event active at a time
  - Broadcasts `EventStart(eventType)` and `EventEnd(eventType)` to all clients via `RemoteEvent`
  - Calls appropriate sub-service on start/end
- [ ] **P2** `src/server/services/EventService.lua` — Monsoon Rain handler
  - On start: iterate all ground `BasePart`s in map and set `Friction` to `Constants.MonsoonFriction`
  - On start: iterate all players, set `Humanoid.WalkSpeed × 0.85`
  - On end: restore original values
  - Fires `UnreliableRemoteEvent` to clients to toggle rain `ParticleEmitter`
- [ ] **P2** `src/server/services/EventService.lua` — Satpol PP Raid handler
  - On start: calls `PoliceService:StartRaid()`
  - On end: calls `PoliceService:EndRaid()`
- [ ] **P2** `src/server/services/EventService.lua` — Flash Mob handler
  - On start: calls `TrafficService:FlashMobBurst()`, sets `EventMultiplier = 0.5` for payout calculations
  - On end: restore spawn weights, clear multiplier

---

## 12. Monetization & Gamepasses

- [ ] **P2** `src/server/services/MonetizationService.lua`
  - `ProcessReceipt(receiptInfo)` — handles `MarketplaceService` purchase callbacks
  - Gamepass checks on join: `MarketplaceService:UserOwnsGamePassAsync()`
    - VIP Whistle: sets `WhistleStat` bonus in player profile
    - Landlord: sets `ExtraSlot = true` in player profile
  - Developer Product handlers:
    - Energy Drink: `CombatService:RefillStamina(player)`
    - Bribe Money: `PoliceService:ClearTargeting(player)`
- [ ] **P2** `src/server/services/MonetizationService.lua` — consumable inventory
  - Server-side consumable counts (Spike Strip, Energy Drink, Bribe Money)
  - In-match shop purchase: validate Shift Currency, deduct, increment count
  - Use: validate count > 0, decrement, apply effect

---

## 13. Client UI Controllers

- [ ] **P1** `src/client/controllers/HUDController.lua`
  - Renders Shift Tracker (timer + currency display)
  - Updates on `EconomyService` change events
  - Renders Stamina Bar, updates on local stamina state
- [ ] **P1** `src/client/controllers/ThreatController.lua`
  - Receives thief-in-zone `UnreliableRemoteEvent`
  - Calculates screen-space direction to threat
  - Shows/hides threat arrow UI element, scales opacity by proximity
- [ ] **P1** `src/client/controllers/TugOfWarController.lua`
  - Receives `TugOfWarStart` event from server
  - Shows Tug-of-War bar above player head (BillboardGui)
  - Sends APM input events to server during active window
  - Hides bar on `TugOfWarResult`
- [ ] **P2** `src/client/controllers/EventController.lua`
  - Receives `EventStart` / `EventEnd` from server
  - Shows event announcement banner with correct variant
  - Toggles rain `ParticleEmitter` for Monsoon
  - Toggles police siren audio loop for Raid
- [ ] **P2** `src/client/controllers/ShopController.lua`
  - Opens in-match shop UI on proximity to Shop vendor
  - Displays 3 consumable cards with prices
  - Fires purchase `RemoteEvent` to server
- [ ] **P2** `src/client/controllers/BankController.lua`
  - Opens bank deposit UI on proximity to Bank Terminal
  - Fires `BankEarnings` `RemoteEvent` to server
  - Updates HUD currency display on confirmation
- [ ] **P2** `src/client/controllers/PostSessionController.lua`
  - Receives shift summary data from server at `ShiftEnd`
  - Renders payout screen: earnings breakdown, penalties, top earner callout
  - Shows "Ready Up" button to trigger next session

---

## 14. Cosmetics System

- [ ] **P2** `src/server/services/CosmeticService.lua`
  - On player join: reads owned cosmetics from DataService
  - Applies vest `MeshPart` swap to player character
  - Applies whistle SFX override (sends SFX asset ID to all clients)
  - Applies trail effect to player character
- [ ] **P2** `src/client/controllers/CosmeticController.lua`
  - Receives cosmetic data from server on join
  - Applies whistle SFX locally (own character uses assigned pitch + cosmetic sound)
  - Renders other players' cosmetic trails via `UnreliableRemoteEvent` updates

---

## 15. Syndicate System

- [ ] **P3** `src/server/services/SyndicateService.lua`
  - Create / join / leave syndicate
  - Max 8 members per syndicate
  - Adjacent zone turf bonus: +5% payout when member zones are neighboring
  - Weekly leaderboard: top 3 syndicates earn cosmetic banner reward (server-side grant)
- [ ] **P3** `src/client/controllers/SyndicateController.lua`
  - Syndicate management UI panel
  - Member list display
  - Contribution bar (week's combined banked earnings)

---

## 16. Anti-Exploit & Sanity Checks

All checks live inside the relevant service, not in a separate module — listed here for audit.

- [ ] **P1** Whistle: rate limit 1/0.5s, stamina server-confirmed
- [ ] **P1** Dash: direction vector normalized server-side, max 45° deviation, stamina server-confirmed, cooldown server-confirmed
- [ ] **P1** Drag confirm: position clamped to zone bounds server-side, ownership verified
- [ ] **P1** Payout claim: vehicle must be in `Parked` state, player ID must match zone owner
- [ ] **P1** Consumable use: inventory count verified server-side before effect fires
- [ ] **P2** Currency transactions: all `AddPayout` / `ApplyPenalty` / `BankEarnings` calls are server-only, no client-accessible `RemoteFunction` for economy writes
- [ ] **P2** APM input (Tug-of-War): server caps accepted inputs per second to prevent macro/autoclicker advantage (max 10 inputs/second accepted)

---

## 17. Optimization & Networking

- [ ] **P1** `src/server/services/PhysicsService.lua`
  - On vehicle creation: set `NetworkOwnership` to server
  - On idle/parked: anchor assembly, disable physics
  - On drag start: unanchor, maintain server `NetworkOwnership`
  - On confirm: re-anchor
- [ ] **P2** Audit all `RemoteEvent` usage — ensure visual-only updates use `UnreliableRemoteEvent`
  - Whistle VFX: `UnreliableRemoteEvent`
  - Dash trail VFX: `UnreliableRemoteEvent`
  - Drag position updates: `UnreliableRemoteEvent`
  - Rain particle toggle: `UnreliableRemoteEvent`
- [ ] **P2** Vehicle count budget: enforce max simultaneous vehicle cap in `TrafficService` to prevent server physics overload
- [ ] **P3** Client-side interpolation for dragged vehicle position (smooth render from server position updates)
