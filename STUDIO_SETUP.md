# Studio Setup Task List: Kang Parkir

All tasks are performed in Roblox Studio or via Rojo project configuration.
Complete these before scripting tasks begin.

---

## Legend

- [ ] = Not started
- [x] = Done
- Priority: **P1** = Must be done before first playtest | **P2** = Required for full feature | **P3** = Polish/QA

---

## 1. Project Structure (Rojo)

- [ ] **P1** Install Rojo plugin in Roblox Studio
- [ ] **P1** Install Rojo CLI on development machine
- [ ] **P1** Create `default.project.json` — map `src/` folders to Roblox service tree:
  ```
  src/server     → ServerScriptService
  src/client     → StarterPlayerScripts
  src/shared     → ReplicatedStorage.Shared
  src/assets     → ReplicatedStorage.Assets (models, VFX)
  ```
- [ ] **P1** Create folder structure in `src/`:
  ```
  src/
  ├── server/
  │   └── services/
  ├── client/
  │   └── controllers/
  ├── shared/
  └── assets/
  ```
- [ ] **P1** Initialize git repository for the project
- [ ] **P1** Add `.gitignore` — exclude `.rbxl` binary file, keep `src/` and config files
- [ ] **P2** Set up `wally.toml` for Wally package manager
- [ ] **P2** Install packages via Wally:
  - `Knit` (sleitnick/knit)
  - `ProfileService` (madstudioroblox/profileservice)
  - `Promise` (evaera/promise)
- [ ] **P2** Add `Packages/` output directory to `default.project.json` → `ReplicatedStorage.Packages`

---

## 2. Roblox Studio Game Settings

- [ ] **P1** Set game name: `Kang Parkir`
- [ ] **P1** Set max players: `8`
- [ ] **P1** Set genre: `Town and City`
- [ ] **P1** Enable **Server-side Scripts** (default) — confirm no legacy LocalScript-only services
- [ ] **P1** Disable **Allow Custom Avatars** (enforce uniform vest cosmetic system)
- [ ] **P1** Set `Workspace.Gravity` to `196.2` (standard Roblox; verify physics feel)
- [ ] **P1** Set `Workspace.StreamingEnabled = false` (small map; streaming not needed, avoids asset pop-in)
- [ ] **P2** Configure **Avatar Type**: R15 only
- [ ] **P2** Configure **Avatar Animations**: Standard (custom anims added per character via script)
- [ ] **P2** Set `Workspace.SignalBehavior = Immediate` (consistent event ordering)

---

## 3. DataStore Setup

- [ ] **P1** Enable **DataStore API** in game settings (Studio → Game Settings → Security → Enable Studio Access to API Services)
- [ ] **P1** Enable **HTTP Requests** in game settings (required by some ProfileService internals)
- [ ] **P1** Define DataStore key naming convention: `PlayerData_[UserId]`
- [ ] **P1** Define ProfileService scope: `KangParkir_v1` (increment on schema breaking change)
- [ ] **P2** Create a mock/stub DataStore for offline Studio testing (set `ProfileService.MockDataStoreEnabled = true` in a dev config)

---

## 4. RemoteEvent & RemoteFunction Setup

Create all network objects under `ReplicatedStorage.Remotes`. Named exactly as referenced in scripts.

### 4.1 Server → Client (FireAllClients / FireClient)

- [ ] **P1** `Remotes.SessionPhaseChanged` — `RemoteEvent`
- [ ] **P1** `Remotes.TugOfWarStart` — `RemoteEvent`
- [ ] **P1** `Remotes.TugOfWarResult` — `RemoteEvent`
- [ ] **P1** `Remotes.PayoutReceived` — `RemoteEvent`
- [ ] **P1** `Remotes.PenaltyApplied` — `RemoteEvent`
- [ ] **P2** `Remotes.EventStart` — `RemoteEvent`
- [ ] **P2** `Remotes.EventEnd` — `RemoteEvent`
- [ ] **P2** `Remotes.ThreatInZone` — `UnreliableRemoteEvent`
- [ ] **P2** `Remotes.RainToggle` — `UnreliableRemoteEvent`
- [ ] **P2** `Remotes.WhistleVFX` — `UnreliableRemoteEvent`
- [ ] **P2** `Remotes.DashTrailVFX` — `UnreliableRemoteEvent`
- [ ] **P2** `Remotes.CosmeticData` — `RemoteEvent`
- [ ] **P2** `Remotes.ShiftSummary` — `RemoteEvent`

### 4.2 Client → Server (FireServer)

- [ ] **P1** `Remotes.WhistleStart` — `RemoteEvent`
- [ ] **P1** `Remotes.WhistleStop` — `RemoteEvent`
- [ ] **P1** `Remotes.TugOfWarInput` — `RemoteEvent`
- [ ] **P1** `Remotes.DragStart` — `RemoteEvent`
- [ ] **P1** `Remotes.DragPositionUpdate` — `UnreliableRemoteEvent`
- [ ] **P1** `Remotes.DragConfirm` — `RemoteEvent`
- [ ] **P1** `Remotes.DashRequest` — `RemoteEvent`
- [ ] **P1** `Remotes.StrikeRequest` — `RemoteEvent`
- [ ] **P2** `Remotes.PlaceStrip` — `RemoteEvent`
- [ ] **P2** `Remotes.BankEarnings` — `RemoteEvent`
- [ ] **P2** `Remotes.ShopPurchase` — `RemoteEvent`
- [ ] **P2** `Remotes.QTEResult` — `RemoteEvent`
- [ ] **P2** `Remotes.ReadyUp` — `RemoteEvent`

---

## 5. CollisionGroup Configuration

Set up in Studio via `PhysicsService` (or script on server init).

- [ ] **P1** Create group `Players`
- [ ] **P1** Create group `DraggedVehicles`
- [ ] **P1** Create group `ParkedVehicles`
- [ ] **P1** Create group `NPCs`
- [ ] **P1** Create group `Environment`
- [ ] **P1** Set collision rules:
  | Group A         | Group B         | Collide? |
  | :-------------- | :-------------- | :------- |
  | DraggedVehicles | Players         | No       |
  | DraggedVehicles | ParkedVehicles  | Yes      |
  | DraggedVehicles | Environment     | Yes      |
  | Players         | NPCs            | Yes      |
  | Players         | Environment     | Yes      |
  | ParkedVehicles  | Environment     | Yes      |

---

## 6. Map Placement in Studio

All placed as `Model` instances under `Workspace`.

- [ ] **P1** Place ground plane (asphalt) and align to `0, 0, 0` origin
- [ ] **P1** Place sidewalks left and right of road
- [ ] **P1** Place parking lot zone `Part`s (4–8 zones), name them `Zone_1` through `Zone_8`
  - Set `Transparency = 0.85`, `CanCollide = false`, `Anchored = true`
  - Tag each with `CollectionService` tag: `ParkingZone`
- [ ] **P1** Place `HidingVolume` parts (4–6 positions)
  - Set `Transparency = 1`, `CanCollide = false`, `Anchored = true`
  - Tag with `CollectionService` tag: `HidingVolume`
- [ ] **P1** Place Traffic Spawn Node (`Part`, invisible): name `TrafficSpawnNode`
- [ ] **P1** Place Traffic Despawn Node (`Part`, invisible): name `TrafficDespawnNode`
- [ ] **P1** Place Thief Despawn Node (`Part`, invisible): name `ThiefDespawnNode`
- [ ] **P1** Place Police Spawn Nodes (2–4 positions, invisible): name `PoliceSpawnNode_1` etc.
- [ ] **P1** Place Citation position (`Part`, invisible): name `CitationNode`
- [ ] **P2** Place Bank Terminal model at fixed position, name `BankTerminal`
  - Add `ProximityPrompt` with `ActionText = "Bank Earnings"`, `ObjectText = "Terminal"`
- [ ] **P2** Place Shop Vendor model at fixed position, name `ShopVendor`
  - Add `ProximityPrompt` with `ActionText = "Open Shop"`, `ObjectText = "Toko"`
- [ ] **P2** Place all street props (carts, signs, clutter) — static, `Anchored = true`, no `CanCollide` on small decorative parts
- [ ] **P3** Place neon signage with emissive `SurfaceAppearance` materials

---

## 7. CollectionService Tags

All server services use `CollectionService:GetTagged()` for spatial queries. Apply tags in Studio to placed instances.

- [ ] **P1** `ParkingZone` — applied to all zone `Part`s
- [ ] **P1** `HidingVolume` — applied to all hiding `Part`s
- [ ] **P1** `SpikeStrip` — applied at runtime by server when strip is placed (no pre-placed instances)
- [ ] **P2** `BankTerminal` — applied to Bank Terminal model
- [ ] **P2** `ShopVendor` — applied to Shop Vendor model
- [ ] **P2** `PoliceSpawnNode` — applied to all police spawn `Part`s
- [ ] **P2** `Vehicle_Scooter` — applied to Scooter model template in `ReplicatedStorage`
- [ ] **P2** `Vehicle_SportBike` — applied to Sport Bike template
- [ ] **P2** `Vehicle_FamilyCar` — applied to Family Car template
- [ ] **P2** `Vehicle_AggroSUV` — applied to Aggro SUV template
- [ ] **P2** `Vehicle_Supercar` — applied to VIP Supercar template

---

## 8. ReplicatedStorage Organization

- [ ] **P1** `ReplicatedStorage/Remotes/` — all `RemoteEvent` and `UnreliableRemoteEvent` instances (created manually or by server init script)
- [ ] **P1** `ReplicatedStorage/Shared/` — synced from `src/shared/` via Rojo
- [ ] **P2** `ReplicatedStorage/Packages/` — Wally-installed packages
- [ ] **P2** `ReplicatedStorage/Assets/Vehicles/` — vehicle model templates (cloned by `TrafficService` at runtime)
- [ ] **P2** `ReplicatedStorage/Assets/NPCs/` — Helmet Thief and Satpol PP rig templates
- [ ] **P2** `ReplicatedStorage/Assets/VFX/` — `ParticleEmitter` and effect templates
- [ ] **P2** `ReplicatedStorage/Assets/UI/` — UI template `ScreenGui` instances (cloned to `PlayerGui` by client controllers)

---

## 9. StarterGui Setup

- [ ] **P1** `StarterGui.ResetPlayerGuiOnSpawn = false` — prevents UI wipe on character respawn
- [ ] **P1** Create `StarterGui/HUD` — `ScreenGui`, `ResetOnSpawn = false`
  - Placeholder `Frame` for Shift Tracker (top center)
  - Placeholder `Frame` for Stamina Bar (bottom left)
  - Placeholder `Frame` for threat arrows (screen edges)
- [ ] **P2** Create `StarterGui/TugOfWarGui` — `BillboardGui` template (attached to character by script)
- [ ] **P2** Create `StarterGui/EventBanner` — slide-in `ScreenGui`, hidden by default
- [ ] **P2** Create `StarterGui/ShopGui` — `ScreenGui`, hidden by default, opened by `ShopController`
- [ ] **P2** Create `StarterGui/BankGui` — `ScreenGui`, hidden by default
- [ ] **P2** Create `StarterGui/PostSessionGui` — `ScreenGui`, hidden by default

---

## 10. Lighting & Atmosphere

- [ ] **P1** Set `Lighting.Ambient` to warm urban tone (RGB ~180, 160, 130)
- [ ] **P1** Set `Lighting.Brightness` to ~2.0 (daytime, high contrast)
- [ ] **P1** Set `Lighting.ClockTime` to `14` (early afternoon)
- [ ] **P2** Add `Atmosphere` instance:
  - `Density = 0.3`
  - `Offset = 0.1`
  - `Color = warm haze (RGB 255, 220, 180)`
- [ ] **P2** Add `ColorCorrection` post-effect:
  - `Saturation = 0.15` (slightly punchy)
  - `Contrast = 0.1`
- [ ] **P3** Add `Bloom` post-effect: `Intensity = 0.3`, `Size = 24` — enhances neon signage glow
- [ ] **P3** Monsoon event: script darkens `Lighting.Brightness` to `1.2` and shifts `Ambient` to cool gray during event

---

## 11. Mobile & Cross-Platform

- [ ] **P1** Verify `StarterGui.ShowDevelopmentGui = false` in published build
- [ ] **P2** Add `StarterGui` virtual joystick support — confirm Roblox built-in mobile controls active
- [ ] **P2** Place action buttons (Whistle, Dash, Smack, Interact) in `StarterGui/HUD` at bottom-right
  - `ImageButton` instances, min 60×60 pixels each
  - Assign `UserInputService` touch events in `CombatController` and `WhistleController`
- [ ] **P2** Test all `ProximityPrompt`s on mobile (verify trigger distance and touch area)
- [ ] **P3** Add settings `ScreenGui` with:
  - Spatial Grid Overlay toggle (fires `UnreliableRemoteEvent` to toggle overlay locally)
  - SFX / Music / Ambient volume sliders

---

## 12. Playtest Checklist (Pre-Release)

Run through before any public playtest build.

- [ ] **P1** Solo playtest: park one of each vehicle type end-to-end (whistle → aggro → drag → confirm → payout)
- [ ] **P1** Solo playtest: verify tip-over penalty fires and currency deducts
- [ ] **P1** Solo playtest: verify Helmet Thief spawns, steals, and can be interrupted
- [ ] **P1** Solo playtest: verify Tug-of-War resolves correctly with 2 test players
- [ ] **P1** Verify DataStore saves and loads correctly across server restart
- [ ] **P2** Full server (8 players) stress test: confirm server framerate stays above 20fps
- [ ] **P2** Mobile device test: verify all touch controls reach minimum tap area
- [ ] **P2** All 3 dynamic events fire and resolve without errors in output
- [ ] **P2** Gamepass purchase flow tested in Studio with mock `MarketplaceService`
- [ ] **P2** Spike Strip placed, triggers on vehicle, voids payout — verified
- [ ] **P3** End-to-end monetization test in published test place (not Studio) using real Robux test purchase
