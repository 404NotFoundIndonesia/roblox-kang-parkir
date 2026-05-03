# Kang Parkir

A physics-based, time-management multiplayer game for Roblox. Players compete as rival street parking attendants ("Tukang Parkir") — whistling vehicles into their lots, wrestling bikes into tight spaces, fighting off helmet thieves, and sabotaging each other in a chaotic Indonesian urban street.

**Genre:** Physics-Based Time-Management / Asymmetrical Multiplayer Action  
**Platform:** Roblox (PC, Mobile, Console)  
**Engine:** Roblox Studio (Luau)  
**Max Players:** 8 per server

---

## Documentation

| File | Contents |
| :--- | :--- |
| [PRD.md](PRD.md) | Product Requirements Document — features, economy, tech spec |
| [GDD.md](GDD.md) | Game Design Document — mechanics, systems, entities, session flow |
| [TASKS.md](TASKS.md) | Scripting task list with function signatures and validation rules |
| [ASSET.md](ASSET.md) | Asset task list — models, VFX, audio, UI sprites |
| [STUDIO_SETUP.md](STUDIO_SETUP.md) | Studio configuration, map placement, collision groups, playtest checklist |

---

## Prerequisites

| Tool | Version | Purpose |
| :--- | :--- | :--- |
| [Roblox Studio](https://www.roblox.com/create) | Latest | Game editor and play-tester |
| [Rojo](https://rojo.space) | 7.x | Syncs `src/` on disk into Roblox Studio |
| [Wally](https://wally.run) | Latest | Roblox package manager (installs Knit, ProfileService, Promise) |
| [Git](https://git-scm.com) | Any | Version control |

---

## Setup

### 1. Clone the repository

```bash
git clone git@github.com:404NotFoundIndonesia/roblox-kang-parkir.git
cd kang-parkir
```

### 2. Install packages

```bash
wally install
```

This creates a `Packages/` folder containing `Knit`, `ProfileService`, and `Promise`. This folder is gitignored — run `wally install` after every fresh clone.

### 3. Start the Rojo sync server

```bash
rojo serve
```

### 4. Connect Studio to Rojo

Open Roblox Studio. In the `Plugins` tab, click `Rojo`, then click `Connect`. Studio will sync the `src/` folder into the game tree in real time.

### 5. Enable API services (one-time, per machine)

In Studio: `File → Game Settings → Security`  
Enable **Allow Studio Access to Roblox Game Services** and **Allow HTTP Requests**.  
These are required for DataStore and ProfileService to work in local playtests.

### 6. Playtest

Press `F5` in Studio (or `Test → Play`) for a solo playtest.  
Press `Test → Start Server + 2 Players` for a local multiplayer session.

---

## Project Structure

```
kang-parkir/
├── src/
│   ├── server/
│   │   ├── init.server.lua          # Boots all Knit services
│   │   └── services/                # Server-only game logic
│   │       ├── DataService.lua
│   │       ├── SessionService.lua
│   │       ├── ZoneService.lua
│   │       ├── TrafficService.lua
│   │       ├── VehicleService.lua
│   │       ├── WhistleService.lua
│   │       ├── TugOfWarService.lua
│   │       ├── StaminaService.lua
│   │       ├── DragService.lua
│   │       ├── CombatService.lua
│   │       ├── EconomyService.lua
│   │       ├── ThiefService.lua
│   │       ├── PoliceService.lua
│   │       ├── EventService.lua
│   │       ├── MonetizationService.lua
│   │       ├── CosmeticService.lua
│   │       ├── PhysicsService.lua
│   │       └── SyndicateService.lua
│   ├── client/
│   │   ├── init.client.lua          # Boots all Knit controllers
│   │   └── controllers/             # Client-only UI and input logic
│   │       ├── WhistleController.lua
│   │       ├── DragController.lua
│   │       ├── CombatController.lua
│   │       ├── HUDController.lua
│   │       ├── ThreatController.lua
│   │       ├── TugOfWarController.lua
│   │       ├── EventController.lua
│   │       ├── ShopController.lua
│   │       ├── BankController.lua
│   │       ├── PostSessionController.lua
│   │       ├── CosmeticController.lua
│   │       └── SyndicateController.lua
│   ├── shared/
│   │   ├── Knit.lua                 # Re-exports Knit from Packages
│   │   ├── Constants.lua            # All tunable game values
│   │   ├── Types.lua                # Luau type definitions
│   │   └── Enums.lua                # String enum tables
│   └── assets/                      # In-Studio assets synced via Rojo
│       ├── Vehicles/
│       ├── NPCs/
│       ├── VFX/
│       ├── Cosmetics/
│       ├── Audio/
│       └── UI/
├── Packages/                        # Wally output (gitignored)
├── default.project.json             # Rojo project config
├── wally.toml                       # Wally dependency manifest
├── wally.lock                       # Wally lockfile (committed)
├── PRD.md
├── GDD.md
├── TASKS.md
├── ASSET.md
├── STUDIO_SETUP.md
├── README.md
└── LICENSE
```

---

## Architecture Overview

### Client / Server Split

All game-state logic runs on the **server** inside Knit Services. The client only handles input, local animations, and UI. No client script has write access to economy, vehicle state, or player stats.

```
Client Controller          RemoteEvent / UnreliableRemoteEvent          Server Service
─────────────────    ──────────────────────────────────────────────    ───────────────
WhistleController  ──▶  WhistleStart (reliable)              ──▶  WhistleService
DragController     ──▶  DragPositionUpdate (unreliable)      ──▶  DragService
CombatController   ──▶  DashRequest (reliable)               ──▶  CombatService
HUDController      ◀──  PayoutReceived (reliable)            ◀──  EconomyService
ThreatController   ◀──  ThreatInZone (unreliable)            ◀──  ThiefService
EventController    ◀──  EventStart / EventEnd (reliable)     ◀──  EventService
```

Critical state (economy, zone ownership, hit detection) uses `RemoteEvent` (reliable).  
Visual-only updates (VFX, particle toggles, drag position) use `UnreliableRemoteEvent`.

### Key Services

| Service | Responsibility |
| :--- | :--- |
| `DataService` | ProfileService wrapper. Loads/saves player data. Auto-saves every 60s. |
| `SessionService` | Session phase timer. `Lobby → WarmUp → PeakShift → RushHour → ShiftEnd`. |
| `VehicleService` | Per-vehicle state machine. Owns all vehicle state transitions. |
| `WhistleService` | Aggro sphere query. Rate-limiting. Feeds `TugOfWarService` on conflict. |
| `DragService` | AlignPosition/AlignOrientation constraint lifecycle. Tip-over detection. Payout on confirm. |
| `CombatService` | Server-side dash hit detection. Melee hit priority. Spike strip placement. |
| `EconomyService` | Unbanked/banked currency. Payout formula. Event multiplier. |
| `ThiefService` | Helmet Thief Behavior Tree. Coroutine-based state machine. |
| `EventService` | Random event scheduler. Delegates to Monsoon/Raid/FlashMob handlers. |

### Physics Rules

- All vehicles have `NetworkOwnership` assigned to the **server** at all times. Clients never own vehicle physics.
- Vehicles are **anchored** (physics sleeping) unless actively being dragged.
- Dragged vehicles use `AlignPosition` + `AlignOrientation` constraints. The server is the constraint owner.
- Client-side interpolation (`RenderStepped` lerp) smooths drag visuals only — it does not affect server position.

---

## Contributing

1. Branch off `main`: `git checkout -b feature/your-feature`
2. Make changes inside `src/` only. Do not commit `.rbxl` files.
3. Follow the task breakdown in [TASKS.md](TASKS.md) for scripting and [STUDIO_SETUP.md](STUDIO_SETUP.md) for Studio configuration.
4. All new `RemoteEvent` handlers on the server must include the sanity checks listed in [TASKS.md § 16](TASKS.md).
5. Open a pull request against `main`.

---

## License

MIT — see [LICENSE](LICENSE).
