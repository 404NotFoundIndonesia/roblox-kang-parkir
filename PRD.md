# Product Requirements Document: Kang Parkir

**Version:** 1.0  
**Platform:** Roblox (PC, Mobile, Console)  
**Genre:** Physics-Based Time-Management / Asymmetrical Multiplayer Action  
**Engine:** Roblox Studio (Luau)

---

## 1. Executive Summary

**Elevator Pitch:**
*Overcooked* meets street brawling. Players take on the role of hyper-competitive street parking attendants ("Tukang Parkir") in a bustling, localized urban environment. They must physically organize vehicles, fend off helmet thieves, sabotage rival players, and manage chaotic dynamic events to build their parking empire.

**Target Audience:**
Mid-core Roblox players (Ages 10–18+). Appeals to fans of highly active simulator games, PvP brawlers, and time-management puzzles.

---

## 2. Gameplay Architecture & Loops

### 2.1 Core Loop Hierarchy

**Micro-Loop (Moment-to-Moment):**
Scan Traffic → Aggro Vehicle (Tug-of-War) → Escort to Zone → Spatial Puzzle (Pack Vehicles) → Defend (Smack Thieves/Rivals) → Collect Payout.

**Macro-Loop (Session-to-Session):**
Accumulate Shift Currency → Purchase In-Match Consumables (Speed boosts, Sabotage traps) → Survive Global Server Events (Raids, Rain, Concerts).

**Meta-Loop (Long-Term Progression):**
Deposit Earnings to Global DataStore → Upgrade Skill Tree (Whistle radius, Strength, Speed) → Unlock Higher-Tier Maps/Zones → Form Syndicates (Guilds).

---

## 3. Mechanics & Systems Specification

### 3.1 Aggro & Pathfinding Control (The Whistle System)

**Mechanic:** Players cast a zone of influence to attract NPC vehicles.

**Implementation:**
- Client triggers whistle action. Server runs a spherical `OverlapParams` query scaled by the player's Whistle Stat.
- **Tug-of-War Conflict:** When two players aggro the same vehicle, server initiates a `TugOfWar` state.
  - Server listens for APM (Actions-Per-Minute / rhythm inputs) from both clients via `RemoteEvents`.
  - Client with the highest input threshold over 1.5 seconds wins.
  - Server updates the vehicle's `PathfindingService` target node to the winner's assigned parking lot coordinate.

### 3.2 Spatial Assembly & Physics ("Street Tetris")

**Mechanic:** Players manually grab and slide motorcycles to maximize grid density.

**Implementation:**
- Motorcycles are multi-part assemblies, anchored/kinematic by default to minimize server physics load.
- On interaction, server unanchors the assembly and attaches it to the player's `HumanoidRootPart` via `AlignPosition` + `AlignOrientation`.
- **Collision Rules:** Dragged vehicles ignore the player's `CollisionGroup` but collide with other vehicles and static environment geometry.
- **Penalty State:** If angular velocity exceeds threshold (vehicle tips over), server fires a penalty event: applies local currency deduction and triggers a domino-effect physics simulation.

### 3.3 AI Threat Mitigation (Helmet Thieves)

**Mechanic:** NPC thieves spawn asynchronously to steal helmets from parked vehicles.

**Implementation:**
- Driven by a custom server-side Behavior Tree (BT).
- **Sequence:** Roam Map → Raycast for High-Value Asset → Approach → `Interact` State (3s timer) → Un-weld Asset → Flee to Despawn Node.
- **Interrupt:** Player melee hit (via `OverlapParams` raycast) interrupts BT, drops asset as physics object, puts thief in `Ragdoll` state for 1 second before fleeing.

### 3.4 PvP Combat & Sabotage

**Mechanic:** Physical disruption of rival players.

**Implementation:**
- **Tackle (Dash):** Client requests dash. Server applies `VectorForce`. Server-side hit detection (overlap) prevents client exploit spoofing.
- **Crowd Control:** Hit players have `Humanoid.PlatformStand = true` (ragdoll) for 1.5 seconds.
- **Traps (Spike Strip):** Deployed by players. On NPC vehicle `PrimaryPart` contact:
  - Vehicle enters "Damaged" state (`WalkSpeed = 0`).
  - NPC owner plays "Angry" animation.
  - Parking payout permanently voided for that cycle.

---

## 4. Entities & Economy

### 4.1 Vehicle Dictionary

| Vehicle Type  | Spacing Footprint | Speed     | Payout Formula     | Special Mechanics                                              |
| :------------ | :---------------- | :-------- | :----------------- | :------------------------------------------------------------- |
| Scooter       | 2×4 Studs         | Medium    | Base × 1.0         | High spawn rate.                                               |
| Sport Bike    | 3×5 Studs         | Fast      | Base × 1.5         | Prone to Helmet Thieves.                                       |
| Family Car    | 8×12 Studs        | Medium    | Base × 3.0         | Blocks line of sight.                                          |
| Aggro SUV     | 9×14 Studs        | Very Fast | Base × 4.0         | Deals damage/knockback to players if path is obstructed.       |
| VIP Supercar  | 10×15 Studs       | Slow      | Base × 10.0        | Triggers client QTE for parking. Collision deducts 50% payout. |

### 4.2 Payout Formula

```
Payout = (BaseVehicleValue + AlignmentBonus) × (1 + EventMultiplier) − Penalties
```

- **AlignmentBonus:** Granted when vehicle is parallel to surrounding vehicles, calculated via `DotProduct` of LookVectors.
- **EventMultiplier:** Set by active server event (default 0).
- **Penalties:** Applied per tip-over, collision, or trap damage event.

---

## 5. Dynamic Server Events

Triggered randomly by `EventController` every 3–7 minutes to disrupt flow state.

| Event               | Effect                                                                                                  |
| :------------------ | :------------------------------------------------------------------------------------------------------ |
| Monsoon Rain        | Global `Workspace` friction lowered. Vehicles slide further when dropped. Player `WalkSpeed` −15%.     |
| Satpol PP Raid      | Pursuit AI spawns. Players must break LoS or enter `HidingVolumes`. Caught = −20% unbanked currency.   |
| Flash Mob / Concert | Spawn controller injects 30+ motorcycles within 10 seconds. Stress-tests APM and spatial management.   |

---

## 6. UI & UX Design

### 6.1 HUD Elements

| Element                | Position           | Description                                                                                    |
| :--------------------- | :----------------- | :--------------------------------------------------------------------------------------------- |
| Shift Tracker          | Top center         | Current session time and banked currency.                                                      |
| Threat Indicators      | Screen edges       | Red directional arrows that pulse when a Thief AI enters the player's owned parking zone.      |
| Spatial Grid Overlay   | Ground (contextual)| Semi-transparent grid appears when dragging a motorcycle. Togglable in settings.               |
| Tug-of-War Bar         | Above player head  | Pressure gauge that fills rapidly during a whistle battle.                                     |

### 6.2 UX Principles

- All feedback must be immediate and unambiguous (sound + visual confirmation per action).
- Mobile touch targets must meet minimum 44×44 stud equivalent tap area.
- Settings must expose: Grid Overlay toggle, audio mix sliders (SFX / Ambient / Music).

---

## 7. Art & Audio Direction

### 7.1 Visual Style

"Stylized Urban" — low-poly models for mobile performance, vibrant saturated textures. Key props: neon signage, street food carts, localized banners. NPCs use highly expressive facial decals.

### 7.2 Audio Design

| Type      | Asset                      | Notes                                                                                         |
| :-------- | :------------------------- | :-------------------------------------------------------------------------------------------- |
| Diegetic  | Traffic hum (loop)         | Constant ambient layer.                                                                       |
| Diegetic  | Whistle blows              | Unique pitch per player to distinguish self from rivals.                                      |
| Feedback  | "Kaching!" coin SFX        | Sharp, dopamine-inducing. Fires on payout collection.                                         |
| Feedback  | Rustling/zipper SFX        | 3D Spatial Audio (`RollOffMode`) cues player attention when a Thief AI interacts with helmet. |

---

## 8. Monetization Strategy

### 8.1 Gamepasses (Permanent)

| Pass         | Effect                                                         |
| :----------- | :------------------------------------------------------------- |
| VIP Whistle  | +20% base aggro radius. Whistle VFX changes to gold.           |
| Landlord     | Unlocks 1 extra premium parking slot per map tier.             |

### 8.2 Developer Products (Consumable / Per-Session)

| Product       | Effect                                          |
| :------------ | :---------------------------------------------- |
| Energy Drink  | Instantly refills stamina/dash meter.           |
| Bribe Money   | Instantly clears player aggro during Raid event.|

### 8.3 Cosmetics (Lootbox / Direct Purchase)

- **Vests:** Neon, Leather Jacket, Cyberpunk UI vest.
- **Whistle Sounds:** Train horn, airhorn, duck quack.
- **Trails:** Custom walk and dash trail effects.

> All monetization must comply with Roblox Terms of Service. No pay-to-win mechanics that gate core gameplay loops.

---

## 9. Technical Architecture & Optimization

### 9.1 Framework

Use Knit (or equivalent modular framework) to enforce strict client/server separation:
- **Client Controllers:** Input handling, VFX, UI updates.
- **Server Services:** Economy, zone ownership, hit detection, AI, event orchestration.

### 9.2 Data Persistence

`ProfileService` for player data management. Prevents data wipes during concurrent sessions or currency trading. Schema versioning required from v1.0.

### 9.3 Networking Strategy

| Traffic Type                                        | Method                    | Rationale                                  |
| :-------------------------------------------------- | :------------------------ | :----------------------------------------- |
| Economy, zone ownership, brawl hit-detection        | `RemoteEvent` (reliable)  | Server-side sanity checks required.        |
| Whistle VFX, dash trails, emote animations          | `UnreliableRemoteEvent`   | Visual only; packet loss acceptable.       |

All client-to-server `RemoteEvent` calls must include server-side validation: rate limiting, range checks, and ownership verification.

### 9.4 Physics Optimization

| Condition                       | Requirement                                                                   |
| :------------------------------ | :---------------------------------------------------------------------------- |
| Vehicle not interacted with     | `NetworkOwnership = Server`. Physics state = sleeping/anchored.               |
| Vehicle being dragged by player | Server unanchors. Client-side interpolation for smooth drag rendering.        |
| Vehicle tipped over             | Server fires penalty event. Re-anchor after domino simulation completes.      |

### 9.5 Performance Targets

| Platform | Target FPS |
| :------- | :--------- |
| PC       | 60 fps     |
| Mobile   | 30 fps     |
| Console  | 60 fps     |

Low-poly asset budget enforced per map. Particle VFX capped per player viewport.

---

## 10. Out of Scope (v1.0)

- Cross-server trading or player marketplace.
- Replay system.
- Ranked/competitive matchmaking (post-launch consideration).
- Voice chat integration.
