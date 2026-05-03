# Studio Setup Task List: Kang Parkir

All tasks performed in Roblox Studio or via terminal/Rojo config.
Done = the described state is verifiable by opening the file, checking the property, or running a playtest.

---

## Legend

- [ ] = Not started
- [x] = Done
- **P1** = Must be done before first playtest | **P2** = Required for full feature | **P3** = Polish/QA

---

## 1. Project Structure (Rojo)

- [ ] **P1** In terminal, run `rojo plugin install` inside the project root to install the Rojo Roblox Studio plugin. Confirm the plugin appears in Studio under `Plugins` tab as `"Rojo"`.

- [ ] **P1** Create `default.project.json` in the project root with the following exact content:
  ```json
  {
    "name": "kang-parkir",
    "tree": {
      "$className": "DataModel",
      "ServerScriptService": {
        "$className": "ServerScriptService",
        "Server": {
          "$path": "src/server"
        }
      },
      "StarterPlayer": {
        "$className": "StarterPlayer",
        "StarterPlayerScripts": {
          "$className": "StarterPlayerScripts",
          "Client": {
            "$path": "src/client"
          }
        }
      },
      "ReplicatedStorage": {
        "$className": "ReplicatedStorage",
        "Shared": {
          "$path": "src/shared"
        },
        "Packages": {
          "$path": "Packages"
        },
        "Assets": {
          "$path": "src/assets"
        }
      }
    }
  }
  ```

- [ ] **P1** Create the following folders on disk so Rojo can sync them (empty folders need a `.gitkeep` file inside):
  ```
  src/server/services/.gitkeep
  src/client/controllers/.gitkeep
  src/shared/.gitkeep
  src/assets/Vehicles/.gitkeep
  src/assets/NPCs/.gitkeep
  src/assets/VFX/.gitkeep
  src/assets/Cosmetics/Vests/.gitkeep
  src/assets/Cosmetics/Trails/.gitkeep
  src/assets/Audio/.gitkeep
  src/assets/UI/.gitkeep
  ```

- [ ] **P1** Run `git init` in the project root. Create `.gitignore` with the following lines:
  ```
  *.rbxl
  *.rbxlx
  Packages/
  .DS_Store
  ```
  The `.rbxl` binary is excluded because it cannot be meaningfully diffed. Source of truth is `src/`.

- [ ] **P2** Create `wally.toml` in the project root with the following content:
  ```toml
  [package]
  name = "yourname/kang-parkir"
  version = "0.1.0"
  registry = "https://github.com/UpliftGames/wally-index"
  realm = "shared"

  [dependencies]
  Knit = "sleitnick/knit@1.5.1"
  ProfileService = "madstudioroblox/profileservice@1.0.0"
  Promise = "evaera/promise@4.0.0"
  ```

- [ ] **P2** Run `wally install` in the project root. Confirm a `Packages/` folder is created containing `Knit`, `ProfileService`, and `Promise` subfolders. These are gitignored; every developer runs `wally install` after cloning.

- [ ] **P2** In `default.project.json`, verify the `"Packages"` path entry points to the `Packages/` output folder so Rojo syncs installed packages into `ReplicatedStorage.Packages` at Studio start. Confirm by running `rojo serve` and opening Studio — `ReplicatedStorage.Packages` should contain the three package modules.

---

## 2. Roblox Studio Game Settings

Navigate to `Home → Game Settings` for all items in this section unless otherwise stated.

- [ ] **P1** In the `Basic Info` tab: set `Name` to `Kang Parkir`. Set `Description` to a placeholder one-line description. These fields are required before publishing.

- [ ] **P1** In the `Basic Info` tab: set `Genre` to `Town and City`.

- [ ] **P1** In the `Players` tab: set `Max Players` to `8`. Set `Spawn Type` to `"All"` (each player spawns at a `SpawnLocation`; one `SpawnLocation` per zone will be placed in map setup).

- [ ] **P1** In the `Players` tab: under `Avatar`, set `Avatar Type` to `R15` only. Set `Animation` to `"Standard"`. Set `Collision` to `"Inner Box"`.

- [ ] **P1** In the `Players` tab: under `Avatar`, disable `Allow Custom Avatars`. This forces all players to use the default rig — vest cosmetics applied by script are the only visual customization.

- [ ] **P1** In the `Explorer`, click `Workspace`. In `Properties`, set:
  - `Gravity` = `196.2`
  - `StreamingEnabled` = `false` (unchecked)
  - `SignalBehavior` = `Immediate`
  These three must be set via the Properties panel, not script, so they apply before any script runs.

- [ ] **P1** In the `Explorer`, confirm `ServerScriptService.LoadStringEnabled` = `false`. This should be false by default — verify it has not been toggled on.

---

## 3. DataStore Setup

- [ ] **P1** In Studio, go to `File → Game Settings → Security`. Enable `Allow Studio Access to Roblox Game Services`. Without this, `DataStoreService` calls return errors in Studio playtests.

- [ ] **P1** In the same `Security` tab, enable `Allow HTTP Requests`. ProfileService's session locking mechanism requires HTTP to function correctly under some edge cases.

- [ ] **P1** Document the DataStore key format in a comment at the top of `DataService.lua`: keys are `"Player_[UserId]"` (e.g. `"Player_123456789"`). The ProfileStore scope string is `"KangParkir_v1"`. If the data schema changes in a way that is not backwards-compatible, increment the scope to `"KangParkir_v2"` — this creates a fresh store and existing data is not migrated automatically.

- [ ] **P2** In `DataService.lua`, add a block guarded by `RunService:IsStudio()` at the top: if running in Studio, set `ProfileService.MockDataStoreEnabled = true`. This prevents test sessions from writing to the live DataStore and polluting production data.

---

## 4. RemoteEvent & RemoteFunction Setup

All `RemoteEvent` and `UnreliableRemoteEvent` objects must exist under `ReplicatedStorage.Remotes` before any script tries to reference them. Create them either manually in Studio Explorer or via a server init script that creates them if they do not already exist.

**Recommended approach:** In `src/server/init.server.lua`, before `Knit.Start()`, run a setup block that creates each remote if `ReplicatedStorage.Remotes:FindFirstChild(name) == nil`. This ensures the folder and remotes exist whether Rojo sync created them or not.

### 4.1 Folder

- [ ] **P1** Create a `Folder` named `Remotes` directly under `ReplicatedStorage`. All remotes live inside this folder. Scripts reference them as `ReplicatedStorage.Remotes.EventName`.

### 4.2 Server → Client Remotes

Create each as the specified class inside `ReplicatedStorage.Remotes`:

- [ ] **P1** `SessionPhaseChanged` — `RemoteEvent`. Payload: `(phase: string, remainingSeconds: number)`. Fired every second by `SessionService` timer loop and on phase transitions.
- [ ] **P1** `TugOfWarStart` — `RemoteEvent`. Payload: `(vehicleId: string)`. Fired to both contesting players.
- [ ] **P1** `TugOfWarResult` — `RemoteEvent`. Payload: `(vehicleId: string, won: boolean)`. Fired to both contesting players after resolution.
- [ ] **P1** `PayoutReceived` — `RemoteEvent`. Payload: `(delta: number, newUnbankedTotal: number)`. Fired after each vehicle is parked and after banking.
- [ ] **P1** `PenaltyApplied` — `RemoteEvent`. Payload: `(delta: number, newUnbankedTotal: number)`. Fired after tip-over, trap damage, or police catch.
- [ ] **P1** `StaminaUpdated` — `UnreliableRemoteEvent`. Payload: `(newValue: number)`. Fired on Heartbeat by `StaminaService`. Use `UnreliableRemoteEvent` because a dropped packet just means one skipped frame of stamina bar animation — no gameplay consequence.
- [ ] **P1** `DragStartResult` — `RemoteEvent`. Payload: `(vehicleId: string, success: boolean, reason: string?)`. Fired by `DragService` in response to `DragStart`.
- [ ] **P2** `EventStart` — `RemoteEvent`. Payload: `(eventType: string)`. Fired to all clients when a dynamic event begins.
- [ ] **P2** `EventEnd` — `RemoteEvent`. Payload: `(eventType: string)`. Fired to all clients when event ends.
- [ ] **P2** `ThreatInZone` — `UnreliableRemoteEvent`. Payload: `(thiefId: string, thiefWorldPos: Vector3)`. Fired to the zone owner only.
- [ ] **P2** `RainToggle` — `UnreliableRemoteEvent`. Payload: `(enabled: boolean)`. Fired to all clients on Monsoon start/end.
- [ ] **P2** `WhistleVFX` — `UnreliableRemoteEvent`. Payload: `(playerUserId: number)`. Fired to all clients to trigger whistle VFX on a character other than the local player.
- [ ] **P2** `DashTrailVFX` — `UnreliableRemoteEvent`. Payload: `(playerUserId: number, trailAssetName: string)`. Fired to all clients to spawn trail VFX on a remote character.
- [ ] **P2** `CosmeticData` — `RemoteEvent`. Payload: `(player: Player, data: table)`. Fired to all clients when a player's cosmetics are loaded.
- [ ] **P2** `ShiftSummary` — `RemoteEvent`. Payload: `(data: table)`. Fired to each player at session end.
- [ ] **P2** `PlayerStunned` — `RemoteEvent`. Payload: `(duration: number)`. Fired to the caught player by `PoliceService`. Client locks all input for `duration` seconds.
- [ ] **P2** `ItemGranted` — `RemoteEvent`. Payload: `(itemName: string)`. Fired to player after a Developer Product is successfully granted.
- [ ] **P2** `ShopPurchaseResult` — `RemoteEvent`. Payload: `(itemName: string, success: boolean, reason: string?, newInventory: table?)`.
- [ ] **P2** `QTEPrompt` — `RemoteEvent`. Payload: `(vehicleId: string, sequence: {string})`. Fired to the player dragging a Supercar on `DragConfirm`.

### 4.3 Client → Server Remotes

- [ ] **P1** `WhistleStart` — `RemoteEvent`. No payload. Server validates stamina and rate limit before acting.
- [ ] **P1** `WhistleStop` — `RemoteEvent`. No payload.
- [ ] **P1** `TugOfWarInput` — `RemoteEvent`. Payload: `(vehicleId: string)`. Server tallies this against the active battle for the sender.
- [ ] **P1** `DragStart` — `RemoteEvent`. Payload: `(vehicleId: string)`.
- [ ] **P1** `DragPositionUpdate` — `UnreliableRemoteEvent`. Payload: `(vehicleId: string, desiredCFrame: CFrame)`. High-frequency position feed while dragging. Use `UnreliableRemoteEvent` — dropped packets are fine, next frame overwrites.
- [ ] **P1** `DragConfirm` — `RemoteEvent`. Payload: `(vehicleId: string, desiredCFrame: CFrame)`. Uses reliable `RemoteEvent` because this triggers a payout.
- [ ] **P1** `DashRequest` — `RemoteEvent`. Payload: `(direction: Vector3)`.
- [ ] **P1** `StrikeRequest` — `RemoteEvent`. No payload (server uses player's HRP position/orientation for hit detection).
- [ ] **P2** `PlaceStrip` — `RemoteEvent`. Payload: `(position: Vector3)`.
- [ ] **P2** `BankEarnings` — `RemoteEvent`. No payload. Server reads the player's current unbanked amount from `EconomyService`.
- [ ] **P2** `ShopPurchase` — `RemoteEvent`. Payload: `(itemName: string)`.
- [ ] **P2** `ConsumeItem` — `RemoteEvent`. Payload: `(itemName: string)`.
- [ ] **P2** `QTEResult` — `RemoteEvent`. Payload: `(vehicleId: string, success: boolean)`.
- [ ] **P2** `ReadyUp` — `RemoteEvent`. No payload. Triggers `SessionService` to count ready players.

---

## 5. CollisionGroup Configuration

Create all groups in `PhysicsService`. The easiest approach is to do this in a `Script` under `ServerScriptService` that runs once at server start before Knit boots, so groups exist before any vehicle or character spawns.

- [ ] **P1** Create collision group `"Players"`. Assign all `BasePart`s of player characters to this group inside a `Players.PlayerAdded → character.Added` callback.

- [ ] **P1** Create collision group `"DraggedVehicles"`. Assigned to a vehicle's `BasePart`s by `DragService` when drag begins.

- [ ] **P1** Create collision group `"ParkedVehicles"`. Assigned to a vehicle's `BasePart`s by `DragService` on confirm / `VehicleService` on park.

- [ ] **P1** Create collision group `"TrafficVehicles"`. Default group for all vehicle `BasePart`s while in `Traffic` or `Aggroed` states.

- [ ] **P1** Create collision group `"NPCs"`. Assigned to Helmet Thief and Satpol PP NPC `BasePart`s on spawn.

- [ ] **P1** Create collision group `"Environment"`. Assigned to all static map geometry parts (ground, walls, props). Set once at startup by iterating `Workspace.Map:GetDescendants()`.

- [ ] **P1** Create collision group `"VehicleHitbox"`. A single invisible `Part` inside each vehicle model (named `"Hitbox"`) that is assigned this group. Used by `WhistleService:OverlapParams` filter to detect only vehicles, not their decorative parts.

- [ ] **P1** Set the following collision rules using `PhysicsService:CollisionGroupSetCollidable(groupA, groupB, false/true)`:

  | Group A          | Group B          | Collide? | Reason                                                      |
  | :--------------- | :--------------- | :------- | :---------------------------------------------------------- |
  | DraggedVehicles  | Players          | **No**   | Player walks through the vehicle they are dragging.        |
  | DraggedVehicles  | ParkedVehicles   | **Yes**  | Dragged vehicle bumps into already-parked vehicles.        |
  | DraggedVehicles  | Environment      | **Yes**  | Dragged vehicle hits walls and ground.                     |
  | DraggedVehicles  | TrafficVehicles  | **Yes**  | Dragged vehicle can collide with incoming traffic.         |
  | DraggedVehicles  | DraggedVehicles  | **Yes**  | Two players dragging at once — their vehicles collide.     |
  | Players          | NPCs             | **Yes**  | Players physically interact with thieves and police.       |
  | Players          | TrafficVehicles  | **Yes**  | AggroSUV knocks back players who block its path.           |
  | Players          | Environment      | **Yes**  | Standard player movement.                                  |
  | NPCs             | Environment      | **Yes**  | NPCs walk on the ground.                                   |
  | NPCs             | TrafficVehicles  | **No**   | Thieves should not be blocked by moving traffic.           |

---

## 6. Map Placement in Studio

All map geometry lives inside a `Folder` named `Map` directly under `Workspace`. Scripts reference environment parts as `Workspace.Map:GetDescendants()`. Organize sub-folders: `Map/Ground`, `Map/Walls`, `Map/Props`, `Map/Nodes`, `Map/Zones`, `Map/HidingVolumes`.

### 6.1 Ground & Road

- [ ] **P1** Create a `Part` in `Map/Ground` named `"Road"`. Set:
  - `Size` = `Vector3.new(24, 1, 120)` (24 studs wide, 120 studs long)
  - `Position` = `Vector3.new(0, -0.5, 0)` (top surface flush with Y=0)
  - `Anchored` = `true`
  - `Material` = `Enum.Material.SmoothPlastic`
  - `BrickColor` = dark gray (asphalt placeholder; final texture applied via `SurfaceAppearance`)
  - `CollisionGroup` = `"Environment"`

- [ ] **P1** Create two `Part`s in `Map/Ground` for sidewalks: `"SidewalkLeft"` and `"SidewalkRight"`. Each:
  - `Size` = `Vector3.new(14, 1, 120)`, `Anchored = true`, `CollisionGroup = "Environment"`
  - `SidewalkLeft.Position` = `Vector3.new(-19, -0.5, 0)` (center at 19 studs left of road center)
  - `SidewalkRight.Position` = `Vector3.new(19, -0.5, 0)`

### 6.2 Parking Zones

Each zone is a flat, invisible `Part` sitting on the sidewalk surface. It defines the boundary that `ZoneService:IsInZone` checks against.

- [ ] **P1** Create 8 `Part`s in `Map/Zones`, named `"Zone_1"` through `"Zone_8"`. Distribute 4 on the left sidewalk and 4 on the right, evenly spaced along the Z axis. Each:
  - `Size` = `Vector3.new(12, 0.2, 20)` (placeholder; tune after seeing map in Studio)
  - `Transparency` = `0.85`
  - `CanCollide` = `false`
  - `Anchored` = `true`
  - `BrickColor` = distinct per zone (e.g., Zone_1 = Red, Zone_2 = Blue, Zone_3 = Green, etc.) so zones are visually identifiable in playtesting.
  - `CollisionGroup` = `"Environment"`
  - Add `CollectionService` tag `"ParkingZone"` to each via `CollectionService:AddTag(part, "ParkingZone")` in a startup script, or manually via the Studio Tag Editor plugin.

- [ ] **P1** For each zone, create a `Part` child named `"EntranceMarker"` at the zone's front edge (toward the road). `Size = Vector3.new(2, 0.1, 2)`, `Transparency = 1`, `CanCollide = false`, `Anchored = true`. `VehicleService` pathfinds NPC vehicles to this marker's position when setting aggro.

### 6.3 Node Markers

All node markers are invisible `Part`s, `Size = Vector3.new(2, 2, 2)`, `Transparency = 1`, `CanCollide = false`, `Anchored = true`, named exactly as referenced in scripts.

- [ ] **P1** Create `Map/Nodes/TrafficSpawnNode`: position at one end of the road (e.g., `Vector3.new(0, 1, -62)`). Vehicles spawn here.

- [ ] **P1** Create `Map/Nodes/TrafficDespawnNode`: position at the other end (e.g., `Vector3.new(0, 1, 62)`). Vehicles are destroyed when their `PrimaryPart` enters this volume. Detect via `Part.Touched` event in `VehicleService`.

- [ ] **P1** Create `Map/Nodes/ThiefDespawnNode`: position off the edge of the map (e.g., `Vector3.new(35, 1, 0)`). Helmet Thief pathfinds here to escape.

- [ ] **P1** Create `Map/Nodes/PoliceSpawnNode_1` through `PoliceSpawnNode_4`: place at 4 corners of the map perimeter. Tag each with `CollectionService` tag `"PoliceSpawnNode"`.

- [ ] **P1** Create `Map/Nodes/CitationNode`: place near the map center, away from the parking zones. Players teleport here when caught by police. `Size = Vector3.new(4, 0.1, 4)`, visible with `BrickColor = Red` during playtesting.

### 6.4 Hiding Volumes

- [ ] **P1** Create 6 `Part`s in `Map/HidingVolumes`, named `"HidingVolume_1"` through `"HidingVolume_6"`. Place them at: 2 alley gaps between shop walls on the left, 2 on the right, 1 inside the shop building entrance, 1 behind the food stall cluster. Each:
  - `Size` = `Vector3.new(6, 8, 6)` (covers a person crouching inside)
  - `Transparency` = `1`
  - `CanCollide` = `false`
  - `Anchored` = `true`
  - Tag each with `CollectionService` tag `"HidingVolume"`.
  - These parts act as opaque blockers for the police LoS raycast — `RaycastParams` must include them in the filter. Confirm the raycast hits a `HidingVolume` part before reaching a player character when the player is inside.

### 6.5 Interactive Fixtures

- [ ] **P2** Place the `BankTerminal` model (from `ReplicatedStorage.Assets`) in `Map/Props`. Position it on the right sidewalk at approximately `Vector3.new(19, 0, -30)`. Inside the model's root `Part`, add a `ProximityPrompt` with:
  - `ActionText` = `"Setor"`
  - `ObjectText` = `"Terminal Bank"`
  - `MaxActivationDistance` = `8`
  - `HoldDuration` = `0`
  - Tag the model root with `CollectionService` tag `"BankTerminal"`.

- [ ] **P2** Place the `ShopVendor` model in `Map/Props`. Position it on the left sidewalk at approximately `Vector3.new(-19, 0, -30)`. Add a `ProximityPrompt` with:
  - `ActionText` = `"Buka Toko"`
  - `ObjectText` = `"Warung Parkir"`
  - `MaxActivationDistance` = `8`
  - `HoldDuration` = `0`
  - Tag the model root with `CollectionService` tag `"ShopVendor"`.

### 6.6 SpawnLocations

- [ ] **P1** Create 8 `SpawnLocation` parts, one per zone, named `"Spawn_Zone_1"` through `"Spawn_Zone_8"`. Place each near the back of its corresponding `Zone_N` Part, away from the road. Set `TeamColor` to neutral. Set `Neutral = true`. `Size = Vector3.new(4, 1, 4)`. Players respawn here after being ragdolled/stunned.

### 6.7 Street Props (Decoration)

- [ ] **P2** Place food cart models (`Map/Props/Carts`): 2 Satay carts, 1 Martabak stall, 1 Es Teh bucket. All `Anchored = true`. Set `CanCollide = false` on individual decorative sub-parts smaller than 1 stud to avoid physics overhead. None of these need `CollectionService` tags.

- [ ] **P2** Place 3 hand-painted `"PARKIR"` board props along the sidewalk edges between zones.

- [ ] **P3** Place neon sign models on shop wall faces. Each neon sign model should have `SurfaceAppearance.ColorMap` set to the sign texture. The neon emissive effect comes from `Material = Enum.Material.Neon` on the bright parts, not from post-processing lights.

---

## 7. CollectionService Tags Summary

This is a complete reference of all tags used at runtime. Any tag missing from a part will cause the associated service to silently skip that part — verify these during playtesting by running `CollectionService:GetTagged("TagName")` in the command bar and checking the count.

| Tag               | Applied To                                        | Applied By                        | Used By                        |
| :---------------- | :------------------------------------------------ | :-------------------------------- | :----------------------------- |
| `ParkingZone`     | Zone_1 through Zone_8 Parts                       | Startup script or Tag Editor      | `ZoneService`, `DragService`   |
| `HidingVolume`    | HidingVolume_1 through _6 Parts                   | Startup script or Tag Editor      | `PoliceService` LoS raycast    |
| `PoliceSpawnNode` | PoliceSpawnNode_1 through _4 Parts                | Startup script or Tag Editor      | `PoliceService:StartRaid`      |
| `BankTerminal`    | BankTerminal model root Part                      | Startup script or Tag Editor      | `BankController` proximity     |
| `ShopVendor`      | ShopVendor model root Part                        | Startup script or Tag Editor      | `ShopController` proximity     |
| `ThiefNPC`        | Helmet Thief NPC model root Part                  | `ThiefService` at runtime on spawn| `CombatService` melee priority |
| `SpikeStrip`      | Spike Strip Part                                  | `CombatService` at runtime on place| `CombatService` melee destroy  |
| `VehicleHitbox`   | The `"Hitbox"` Part inside each vehicle model     | Pre-applied in ReplicatedStorage template | `WhistleService` OverlapParams |

- [ ] **P1** Verify tags for `ParkingZone`, `HidingVolume`, `PoliceSpawnNode` are applied to all relevant parts in the map. Run in Studio command bar:
  ```lua
  local CS = game:GetService("CollectionService")
  print("ParkingZone:", #CS:GetTagged("ParkingZone"))   -- expect 8
  print("HidingVolume:", #CS:GetTagged("HidingVolume")) -- expect 6
  print("PoliceSpawnNode:", #CS:GetTagged("PoliceSpawnNode")) -- expect 4
  ```

---

## 8. ReplicatedStorage Organization

The folder structure below must match what scripts reference. Rojo creates most of these via `default.project.json`. Any folder that holds in-Studio assets (not synced from disk) must be created manually.

- [ ] **P1** Confirm `ReplicatedStorage.Remotes` folder exists (created by server init script or manually). All `RemoteEvent`/`UnreliableRemoteEvent` objects live here.

- [ ] **P1** Confirm `ReplicatedStorage.Shared` exists and contains the Rojo-synced scripts from `src/shared/`.

- [ ] **P2** Confirm `ReplicatedStorage.Packages` contains `Knit`, `ProfileService`, `Promise` after `wally install` + Rojo sync.

- [ ] **P2** Create `ReplicatedStorage.Assets.Vehicles` folder. Place one vehicle model template per vehicle type here, named exactly: `"Scooter"`, `"SportBike"`, `"FamilyCar"`, `"AggroSUV"`, `"Supercar"`. Each model must have a `PrimaryPart` set to its chassis base Part, and a `Part` child named `"Hitbox"` tagged `"VehicleHitbox"`.

- [ ] **P2** Create `ReplicatedStorage.Assets.NPCs` folder. Place `"HelmetThief"` and `"SatpolPP"` humanoid rig model templates here. Each must have a `Humanoid` named `"Humanoid"` and a `HumanoidRootPart`.

- [ ] **P2** Create `ReplicatedStorage.Assets.VFX` folder. Place the following templates: `"WhistleRing"` (`ParticleEmitter` inside an `Attachment`), `"DashTrail"` (`Trail` with two `Attachment`s), `"RainEmitter"` (`ParticleEmitter`), `"GridOverlay"` (a flat semi-transparent `Part` sized 1×0.1×1 stud, tiled by script).

- [ ] **P2** Create `ReplicatedStorage.Assets.Cosmetics.Vests` folder. Place each vest `MeshPart` template: `"Default"`, `"Neon"`, `"Leather"`, `"Cyberpunk"`, `"GoldFoil"`, `"Camo"`.

- [ ] **P2** Create `ReplicatedStorage.Assets.Cosmetics.Trails` folder. Place each trail template model (each is an `Attachment`+`Trail` pair inside a `Model`): `"Smoke"`, `"Sparks"`, `"Coins"`, `"NeonLine"`.

- [ ] **P2** Create `ReplicatedStorage.Assets.Audio` folder. Upload and place:
  - `"TrafficAmbient"` — `Sound`, looped, `SoundId` set to the uploaded asset ID
  - `"PoliceSiren"` — `Sound`, looped
  - `"RainAmbient"` — `Sound`, looped
  - `"CrowdChant"` — `Sound`, looped
  - `"Kaching"` — `Sound`, not looped
  - `"CrashTipOver"` — `Sound`, not looped
  - `"TackleImpact"` — `Sound`, not looped
  - `"TugOfWarWin"` — `Sound`, not looped
  - `"WhistleBase"` — `Sound`, not looped (pitch varied at runtime by `CosmeticController`)
  - Whistle cosmetic SFX: `"WhistleTrain"`, `"WhistleAirhorn"`, `"WhistleDuck"`, `"WhistleVuvuzela"`, `"WhistleReferee"` — each a `Sound`

---

## 9. StarterGui Setup

- [ ] **P1** In `StarterGui` properties, set `ResetPlayerGuiOnSpawn` = `false`. Without this, every time a player's character respawns, all `ScreenGui` objects are destroyed and recreated — this would break HUD state.

- [ ] **P1** Create `StarterGui/HUD` — a `ScreenGui` with `ResetOnSpawn = false`. Add the following children (placeholder UI; final visual design applied later):
  - `ShiftTracker` — `Frame`, `Position = UDim2.new(0.35, 0, 0, 8)`, `Size = UDim2.new(0.3, 0, 0, 44)`. Children: `TimeLabel` (`TextLabel`), `UnbankedLabel` (`TextLabel`), `BankedLabel` (`TextLabel`).
  - `StaminaBar` — `Frame`, `Position = UDim2.new(0.02, 0, 0.88, 0)`, `Size = UDim2.new(0.2, 0, 0, 12)`. Child: `Fill` (`Frame`, `BackgroundColor3 = green`).
  - `ThreatArrow` — `ImageLabel`, `Size = UDim2.new(0, 32, 0, 32)`, `Visible = false`. Image set to the red arrow sprite asset ID. Positioned at screen edges by `ThreatController`.
  - `ActionButtons` (mobile) — `Frame`, `Position = UDim2.new(0.72, 0, 0.7, 0)`, `Size = UDim2.new(0.25, 0, 0.28, 0)`. Children: `WhistleBtn`, `DashBtn`, `StrikeBtn`, `InteractBtn` — each an `ImageButton`, `Size = UDim2.new(0, 60, 0, 60)`, positioned in a 2×2 grid. All `Visible = true`; `CombatController` and `WhistleController` bind these.

- [ ] **P2** Create `StarterGui/TugOfWarGui` — a `BillboardGui` template. Set `Size = UDim2.new(0, 160, 0, 24)`. `StudsOffset = Vector3.new(0, 3, 0)`. `AlwaysOnTop = true`. Children: `Background` (`Frame`), `FillLeft` (`Frame`, red, anchored left), `FillRight` (`Frame`, blue, anchored right), `Pin` (`Frame`, 2px wide, centered). `Enabled = false` by default — `TugOfWarController` parents a clone of this to the local player's `HumanoidRootPart` when a battle starts.

- [ ] **P2** Create `StarterGui/EventBanner` — a `ScreenGui`. Child: `Frame` named `Banner`, `Size = UDim2.new(1, 0, 0, 60)`, `Position = UDim2.new(0, 0, -0.1, 0)` (off-screen above). Child of `Banner`: `TitleLabel` (`TextLabel`, `Size = UDim2.new(1, 0, 1, 0)`). `EventController` tweens `Banner.Position` to `UDim2.new(0,0,0.08,0)` on event start and back to `UDim2.new(0,0,-0.1,0)` after 4 seconds.

- [ ] **P2** Create `StarterGui/ShopGui` — a `ScreenGui`, `Enabled = false`. Add a `Frame` named `Panel`, `Size = UDim2.new(0, 320, 0, 200)`, centered. Add 3 `Frame` children named `Item_SpikeStrip`, `Item_EnergyDrink`, `Item_BribeMoney` — each with a `TextLabel` for item name, `TextLabel` for price, `TextLabel` for owned count, and a `TextButton` named `BuyBtn`.

- [ ] **P2** Create `StarterGui/BankGui` — a `ScreenGui`, `Enabled = false`. Add a `Frame`, centered, `Size = UDim2.new(0, 240, 0, 120)`. Children: `UnbankedLabel` (`TextLabel`), `ConfirmBtn` (`TextButton`, text `"SETOR"`), `CancelBtn` (`TextButton`, text `"Batal"`).

- [ ] **P2** Create `StarterGui/PostSessionGui` — a `ScreenGui`, `Enabled = false`. Add a `Frame` covering full screen. Children: `EarnedLabel`, `PenaltiesLabel`, `BankedLabel`, `TopEarnerLabel`, `ReadyBtn` (`TextButton`, text `"SIAP"`).

- [ ] **P2** Create `StarterGui/QTEHUD` — a `ScreenGui`, `Enabled = false`. Add a `Frame` centered, `Size = UDim2.new(0, 300, 0, 80)`. Children: `TimerBar` (`Frame` with `Fill` child), `Prompt` (`TextLabel`, text `"PARKIRKAN DENGAN SEMPURNA!"`), `Btn1`, `Btn2`, `Btn3` — three `TextButton`s arranged horizontally, each 60×60. `DragController` shows this when parking a Supercar.

---

## 10. Lighting & Atmosphere

- [ ] **P1** In `Explorer`, click `Lighting`. Set in `Properties`:
  - `Ambient` = `Color3.fromRGB(180, 160, 130)` (warm, slightly orange)
  - `Brightness` = `2`
  - `ClockTime` = `14` (2 PM)
  - `GeographicLatitude` = `-7` (approximate Indonesian latitude for sun angle)
  - `GlobalShadows` = `true`
  - `ShadowSoftness` = `0.25`

- [ ] **P2** Add an `Atmosphere` instance inside `Lighting`. Set:
  - `Density` = `0.3`
  - `Offset` = `0.1`
  - `Color` = `Color3.fromRGB(255, 220, 180)`
  - `Decay` = `Color3.fromRGB(104, 91, 72)`
  - `Glare` = `0`
  - `Haze` = `1`

- [ ] **P2** Add a `ColorCorrection` post-processing effect inside `Lighting`. Set:
  - `Saturation` = `0.15`
  - `Contrast` = `0.1`
  - `Brightness` = `0`
  - `TintColor` = `Color3.fromRGB(255, 255, 255)` (no tint)

- [ ] **P3** Add a `Bloom` post-processing effect inside `Lighting`. Set:
  - `Intensity` = `0.3`
  - `Size` = `24`
  - `Threshold` = `0.95`
  This makes `Neon` material parts (neon signs) glow visibly. Do not raise `Intensity` above `0.5` — it will blow out the entire scene on mobile.

- [ ] **P3** The Monsoon event's lighting change is scripted (not set here): `EventService._StartMonsoon()` tweens `Lighting.Brightness` to `1.2` and `Lighting.Ambient` to `Color3.fromRGB(120, 130, 140)` over 2 seconds using `TweenService`. `_EndMonsoon()` tweens back to the original values stored before the event started.

---

## 11. Mobile & Cross-Platform

- [ ] **P1** In `StarterGui` properties, confirm `ShowDevelopmentGui` = `false`. This hides the Roblox top bar developer tools in published builds.

- [ ] **P2** Confirm Roblox built-in mobile virtual joystick is active: in `StarterPlayer` properties, set `EnableMouseLockOption = false` (mobile does not use mouse lock). The default Roblox mobile D-pad is enabled automatically when `UserInputService.TouchEnabled = true`; no custom implementation needed for movement.

- [ ] **P2** Verify all 4 action buttons in `HUD.ActionButtons` (`WhistleBtn`, `DashBtn`, `StrikeBtn`, `InteractBtn`) have `Size = UDim2.new(0, 60, 0, 60)` minimum. In Studio, use `View → Device Emulator → iPhone SE (375×667)` to confirm all 4 buttons are reachable with the right thumb without overlap. Adjust positions if any button is within 8px of the screen edge.

- [ ] **P2** Test all `ProximityPrompt`s on mobile by using `Device Emulator`. The `ProximityPrompt` must show a tap-to-activate UI element at the bottom of the screen when the player is within `MaxActivationDistance`. Confirm the `BankTerminal` and `ShopVendor` prompts trigger correctly.

- [ ] **P2** In `CombatController` and `WhistleController`, all input bindings use `UserInputService.InputBegan` with a conditional: `if not gameProcessedEvent then`. This prevents the action from firing when the player taps a UI button (which also triggers `InputBegan`). Verify this by playtesting — tapping the shop button should not also trigger a dash.

- [ ] **P3** Create `StarterGui/SettingsGui` — a `ScreenGui` opened by a gear button in `HUD`. Add:
  - A `ToggleButton` (checkmark style) labeled `"Grid Overlay"`: when toggled off, `DragController` skips rendering the `GridOverlay` Part during drag mode.
  - Three `Slider` `Frame`s (custom UI, not a Roblox default widget) for SFX volume, Music volume, and Ambient volume. Each slider's `TextBox` `Changed` event calls `SoundService:SetVolume(groupName, value)` locally.

---

## 12. Playtest Checklist (Pre-Release)

Run every item below in a Studio playtest before publishing to players. For multiplayer tests, use `Test → Start Server + 2 Players` in Studio.

- [ ] **P1** **Core loop — single player**: Press F to whistle near a Scooter. Confirm the Scooter deviates from traffic and navigates to your zone entrance. Interact with it to enter Drag Mode. Confirm the grid overlay appears. Drag the Scooter into the zone and release. Confirm the `"+N"` payout popup appears and `HUD.ShiftTracker.UnbankedLabel` updates to a non-zero value.

- [ ] **P1** **Tip-over penalty**: While dragging a Scooter, rapidly rotate your camera to spin the vehicle. Confirm the `"-N"` penalty popup fires when angular velocity threshold is exceeded and the vehicle detaches from drag mode.

- [ ] **P1** **Helmet Thief**: Wait for a Helmet Thief to spawn (confirm it spawns within 5 minutes). Watch it navigate to a parked Sport Bike. Confirm the threat HUD arrow appears on the left edge of the screen pointing toward the thief. Walk up and press E to strike. Confirm the thief ragdolls, the helmet drops as a physics object, and the thief resumes roaming.

- [ ] **P1** **DataStore round-trip**: Park several vehicles to accumulate shift currency. Walk to the `BankTerminal`. Press `Setor`. Confirm `UnbankedLabel` drops to 0 and `BankedLabel` increments. In Studio's command bar, run `print(game:GetService("Players"):GetPlayers()[1].UserId)` to get your UserId. Stop the playtest and restart the server. Rejoin. Confirm the `BankedLabel` shows the same value as before the restart.

- [ ] **P1** **Tug-of-War — 2 players**: With 2 test clients, both whistle at the same Scooter simultaneously. Confirm the `TugOfWarGui` bar appears above both characters. Mash a key on one client. Confirm the bar tilts toward that client and after 1.5 seconds, that client's character receives the vehicle and the other gets the red loss flash.

- [ ] **P2** **Full 8-player stress test**: Start a server with 8 simultaneous test clients. Confirm all zones are assigned. Let the session run to the Flash Mob event. Confirm the server does not drop below 20 FPS (monitor via Studio's `Stats.FrameTime` or the server-side FPS display). Confirm no vehicles are lost or duplicated.

- [ ] **P2** **Mobile form factor**: Open Studio's Device Emulator set to `Phone (Small)`. Confirm all 4 action buttons are visible and do not overlap each other or the joystick. Tap each button and confirm the corresponding action fires (check Output for the RemoteEvent arriving on the server). Confirm `ProximityPrompt` UI appears when approaching `BankTerminal`.

- [ ] **P2** **All 3 dynamic events**: In the Studio command bar, fire each event manually by calling `game.ServerScriptService.Server.Services.EventService:_StartEvent("MonsoonRain")` (adjust path if different). Confirm: Monsoon darkens the scene and shows rain particles; Raid spawns 3 Satpol PP NPCs that chase players; Flash Mob injects 30+ Scooters within 10 seconds. Confirm each event ends cleanly (run `_EndEvent` manually) and all modified properties restore to their original values.

- [ ] **P2** **Gamepass + Developer Product**: In Studio with `MockDataStoreEnabled = true` and a test place enabled for purchases, simulate a VIP Whistle gamepass purchase by calling `MonetizationService:_HandleGamepassOwned(localPlayer, "VIPWhistle")` from the command bar. Confirm whistle radius in `WhistleService` is 20% larger than base. Test Energy Drink purchase via `ShopGui` — confirm stamina bar fills immediately after buying.

- [ ] **P2** **Spike Strip**: Buy a Spike Strip from the shop. Place it on the road using the PlaceStrip binding. Drive a traffic Scooter over it (use the whistle to aggro it, then cancel aggro so it returns to traffic path over the strip). Confirm the Scooter enters the Damaged state (stops moving), the NPC plays the angry animation, and the strip disappears. Confirm no payout is generated for that vehicle.

- [ ] **P3** **Monetization end-to-end in published test place**: Publish to a test universe with Robux purchases enabled. Use the Roblox mobile app (not Studio) to test buying the `VIP Whistle` gamepass with a test account. Confirm `ProcessReceipt` returns `PurchaseGranted`, the gamepass bonus is applied next time that account joins, and the purchase is not double-granted on rejoin.
