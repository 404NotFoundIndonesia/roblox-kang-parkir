# Game Design Document: Kang Parkir

**Version:** 1.0  
**Engine:** Roblox Studio (Luau)  
**Genre:** Physics-Based Time-Management / Asymmetrical Multiplayer Action  
**Platform:** PC, Mobile, Console (via Roblox)

---

## Table of Contents

1. [Game Overview](#1-game-overview)
2. [Player Experience Goals](#2-player-experience-goals)
3. [Core Mechanics](#3-core-mechanics)
4. [Player Character](#4-player-character)
5. [NPC Design](#5-npc-design)
6. [Vehicle Design](#6-vehicle-design)
7. [Map & Zone Design](#7-map--zone-design)
8. [Progression System](#8-progression-system)
9. [Economy Design](#9-economy-design)
10. [Dynamic Events](#10-dynamic-events)
11. [Multiplayer Design](#11-multiplayer-design)
12. [UI & HUD Design](#12-ui--hud-design)
13. [Art Direction](#13-art-direction)
14. [Audio Design](#14-audio-design)
15. [Monetization Design](#15-monetization-design)
16. [Session Structure](#16-session-structure)

---

## 1. Game Overview

### 1.1 Concept

**Kang Parkir** is a chaotic, physics-driven multiplayer game set in a stylized Indonesian urban street. Players compete as rival street parking attendants ("Tukang Parkir"), physically wrestling vehicles into parking slots, defending against NPC thieves, sabotaging rivals, and surviving server-wide chaos events — all within a timed shift.

The fantasy is: *you are the most aggressive, territorial, whistle-blowing parking guy on the block.*

### 1.2 Core Pillars

| Pillar         | Description                                                                 |
| :------------- | :-------------------------------------------------------------------------- |
| **Chaos**      | Every session is unpredictable. Dynamic events, rival players, and rogue NPCs create constant disruption. |
| **Territory**  | Space is scarce. Owning and defending your zone is as important as filling it. |
| **Physicality**| Interactions are tactile. Vehicles behave like real objects. Bodies fly. Helmets drop. |
| **Escalation** | Sessions start manageable and spiral into mayhem. The player who adapts wins. |

### 1.3 Unique Selling Points

- Localized Indonesian street culture aesthetic rarely seen in Roblox games.
- Physics-based parking as a skill expression system ("Street Tetris").
- Asymmetric PvP where disruption is as valid a strategy as efficiency.
- Layered loop design that rewards both new and experienced players differently.

---

## 2. Player Experience Goals

### 2.1 First-Session Player (New)

- Feels the core loop within 60 seconds of joining.
- Successfully parks at least 3 vehicles without a tutorial popup gate.
- Has at least one "that was chaos and I loved it" moment by end of session.

### 2.2 Regular Player (5–20 sessions)

- Has a preferred playstyle (aggressive PvP vs. efficient parking vs. event survivor).
- Has unlocked at least one Skill Tree node that changes how they play.
- Has experienced every dynamic event at least once.

### 2.3 Invested Player (20+ sessions)

- Participates in a Syndicate (Guild).
- Has a personalized loadout (cosmetics, consumables).
- Competes for top shift earnings leaderboard.

---

## 3. Core Mechanics

### 3.1 The Whistle System (Aggro)

**Purpose:** Primary tool for directing vehicle flow. Skill expression comes from radius management and timing.

**How It Works:**
1. Player presses/holds the Whistle input.
2. Client fires a `RemoteEvent` to the server.
3. Server runs a spherical `OverlapParams` query. Radius = `BaseWhistleRadius + (WhistleStat × ScalingFactor)`.
4. All unheld, unowned NPC vehicles within the sphere set the player as their current `PathfindingService` target.
5. Vehicle navigates toward the player's assigned parking lot entrance node.

**Whistle Tug-of-War:**
- Triggered when two players' whistle spheres overlap on the same vehicle.
- Server flags vehicle as `TugOfWar = true` and halts standard pathfinding.
- Both players' clients receive a prompt to mash/rhythm-input.
- Server tracks cumulative input score per player over 1.5 seconds.
- Winner's score threshold claimed. Vehicle resumes pathfinding to winner's lot.
- Loser gets a 0.5-second whistle cooldown penalty.

**Design Notes:**
- Whistle radius is the first Skill Tree upgrade. Immediately impactful to new players.
- A player with a large radius can "bully" the entire street but becomes predictable — skilled rivals learn to contest at the edge of the sphere.

### 3.2 Vehicle Parking ("Street Tetris")

**Purpose:** Skill-expressive spatial puzzle. Denser packing = higher AlignmentBonus.

**How It Works:**
1. When a vehicle arrives at the lot entrance, it idles and awaits placement.
2. Player interacts with vehicle to enter "Drag Mode".
3. Server unanchors the assembly and transfers positional control via `AlignPosition`/`AlignOrientation` constraints attached to the player's `HumanoidRootPart`.
4. A transparent grid overlay appears on the ground within the player's lot.
5. Player slides the vehicle into the desired grid cell.
6. Player confirms placement (releases interact input). Server re-anchors the vehicle.

**AlignmentBonus Calculation:**
- On confirm, server samples the `LookVector` of the placed vehicle and each adjacent vehicle.
- `DotProduct` ≥ 0.98 (within ~11°) = perfect alignment. Bonus applied.
- Bonus amount scales with consecutive aligned vehicles (chain bonus).

**Tip-Over Penalty:**
- If the vehicle's angular velocity exceeds `TipThreshold` (tunable, ~15 rad/s) while in Drag Mode:
  - Server detaches constraints and lets physics simulate freely.
  - Domino check: adjacent vehicles within 1.5 stud range inherit a collision impulse.
  - Player receives a currency penalty equal to 30% of that vehicle's base payout.
  - Vehicle must be re-righted before it can be parked (or it despawns after 20 seconds).

### 3.3 Tackle (Dash)

**Purpose:** Primary PvP engagement tool. Interrupts rival actions, triggers ragdoll.

**How It Works:**
1. Player inputs Dash. Client sends `RemoteEvent` with intended direction vector (normalized).
2. Server validates: cooldown check, stamina check, direction sanity check (max 45° deviation from character facing).
3. Server applies a `VectorForce` impulse to the player's `HumanoidRootPart`.
4. During the dash frame window (0.3s), server runs continuous `OverlapParams` checks at player position.
5. Any rival player `HumanoidRootPart` within the overlap box triggers a hit:
   - Hit player: `Humanoid.PlatformStand = true` for 1.5 seconds (ragdoll).
   - Hit player: any vehicle they are currently dragging is forcibly detached (constraints removed).
   - Attacker: dash ends immediately on hit contact.

**Stamina:**
- Shared resource with the Whistle (whistling drains stamina slowly; dashing drains a fixed chunk).
- Regenerates at a base rate passively. Energy Drink consumable refills instantly.

### 3.4 Melee Strike (Smack)

**Purpose:** Short-range tool for hitting Helmet Thieves and disrupting adjacent rivals.

**How It Works:**
1. Player inputs Strike.
2. Server fires a short `OverlapParams` box in front of the player (range: ~3 studs, width: ~2 studs).
3. Hit detection priority: Helmet Thief NPC > Rival Player > Vehicle.
4. On NPC Thief hit: interrupts Behavior Tree, drops stolen asset as physics object, applies Ragdoll to NPC for 1 second.
5. On Rival Player hit: applies a small knockback impulse (not full ragdoll). Interrupts current action (Drag Mode exits, Whistle cancelled).

### 3.5 Spike Strip Trap

**Purpose:** Passive area-denial tool. Rewards positional play.

**How It Works:**
1. Player purchases Spike Strip consumable from in-match shop.
2. Player places it at a valid ground position within 5 studs of themselves.
3. Spike Strip is a physics part owned by the server, tagged with the deploying player's ID.
4. Any NPC vehicle's `PrimaryPart` touching the Strip triggers a `Touched` event:
   - Vehicle enters "Damaged" state: `WalkSpeed = 0`, plays "Angry" NPC animation.
   - That vehicle's payout is permanently voided for its current parking cycle.
   - Strip is consumed (destroyed) after triggering.
5. Rival players can destroy an enemy Strip by striking it (1 hit).

---

## 4. Player Character

### 4.1 Stats

| Stat            | Base Value | Max Value | Upgrade Source     | Effect                                                        |
| :-------------- | :--------- | :-------- | :----------------- | :------------------------------------------------------------ |
| Whistle Radius  | 10 studs   | 22 studs  | Skill Tree (3 tiers)| Sphere radius for vehicle aggro.                             |
| Strength        | 1.0        | 2.0       | Skill Tree (3 tiers)| Multiplies dash knockback force and melee interrupt duration. |
| Speed           | 16         | 22        | Skill Tree (3 tiers)| `WalkSpeed`. Affects how quickly player repositions.          |
| Stamina Pool    | 100        | 160       | Skill Tree (2 tiers)| Total stamina available for whistle and dash.                 |

### 4.2 Action States

| State         | Transitions In                   | Transitions Out                         | Restrictions                             |
| :------------ | :------------------------------- | :-------------------------------------- | :--------------------------------------- |
| Idle          | Default                          | Any input                               | None.                                    |
| Whistling     | Hold whistle input               | Release whistle input, stamina depleted | Cannot dash. Walk speed −20%.            |
| Drag Mode     | Interact with vehicle            | Confirm place, Struck by rival, Ragdoll | Cannot whistle or dash.                  |
| Dashing       | Dash input (stamina check)       | Hit contact, 0.3s elapsed              | No other inputs accepted during dash.    |
| Ragdoll       | Hit by tackle or vehicle (Aggro SUV) | 1.5s elapsed                        | All inputs locked.                       |
| Hiding        | Enter `HidingVolume` during Raid | Exit volume, Raid event ends            | Cannot whistle or dash.                  |

---

## 5. NPC Design

### 5.1 Vehicle NPCs

Vehicle NPCs are not sentient agents — they are physics assemblies driven by `PathfindingService`. Their "behavior" is entirely directed by player whistle input or default traffic logic.

**Default Traffic State (No Player Aggro):**
- Vehicles enter the map from a spawn node at one end of the street.
- Follow a pre-baked waypoint path through the traffic lane.
- Exit at the far end despawn node after a configurable timeout (30–60 seconds).
- If no player aggros them before timeout, no payout is generated.

**Aggro State:**
- Vehicle deviates from traffic path and navigates to the winning player's lot entrance node.
- Idles at entrance awaiting player interaction (Drag Mode).
- If player does not interact within 15 seconds, vehicle re-enters traffic and continues toward exit.

### 5.2 Helmet Thief NPC

Driven by a server-side Behavior Tree. One or more spawn asynchronously during a session.

**Behavior Tree:**

```
Root (Selector)
├── Sequence: Steal
│   ├── Condition: High-value asset exists on map (helmet on parked Sport Bike)
│   ├── Action: Navigate to asset (PathfindingService)
│   ├── Action: Interact (3s timer, plays rummage animation)
│   ├── Action: Un-weld asset from vehicle
│   └── Action: Navigate to despawn node (flee)
└── Action: Roam (random waypoint patrol)
```

**Interrupt (Player Hit):**
- `OverlapParams` melee hit from any player interrupts any active Sequence node.
- Asset drops as unanchored physics object at current thief position.
- Thief enters `Ragdoll` state for 1 second.
- After ragdoll: resumes Roam behavior (does not re-attempt steal for 10 seconds).

**Spawn Rules:**
- Max 2 Helmet Thieves alive simultaneously per server.
- Respawn delay: 45–90 seconds after despawn.
- Priority target: Sport Bikes with helmets attached.

### 5.3 Satpol PP (Police) NPC — Event Only

Spawned exclusively during the Satpol PP Raid event.

**Behavior:**
- Pursuit AI. Targets the nearest player not inside a `HidingVolume`.
- If within 3 studs of target for 2 continuous seconds: "Caught" state triggers.
  - Target player loses 20% of current unbanked shift currency.
  - Player is teleported to a designated "Citation" position and stunned for 3 seconds.
- Police NPC uses Line-of-Sight raycast to detect players. `HidingVolumes` block the raycast.
- Despawns when event ends.

---

## 6. Vehicle Design

### 6.1 Vehicle Dictionary

| Vehicle     | Footprint   | Speed      | Base Payout | Helmet Thief Target | Special Rule                                                |
| :---------- | :---------- | :--------- | :---------- | :------------------ | :---------------------------------------------------------- |
| Scooter     | 2×4 studs   | Medium     | 10          | No                  | High spawn rate. Fills lots quickly but low value.          |
| Sport Bike  | 3×5 studs   | Fast       | 15          | Yes                 | Helmet is a weld-able asset. Losing it voids 40% of payout. |
| Family Car  | 8×12 studs  | Medium     | 30          | No                  | Large footprint. Blocks NPC sightlines. Hard to align.      |
| Aggro SUV   | 9×14 studs  | Very Fast  | 40          | No                  | If path is blocked by a player, applies knockback + ragdoll to that player. |
| VIP Supercar| 10×15 studs | Slow       | 100         | No                  | Triggers a client-side QTE on placement confirmation. QTE success = full payout. QTE fail = 50% payout. Collision in Drag Mode = 50% payout deduction. |

### 6.2 Payout Formula

```
Payout = (BaseVehicleValue + AlignmentBonus) × (1 + EventMultiplier) − Penalties
```

| Variable         | Source                                                                 |
| :--------------- | :--------------------------------------------------------------------- |
| BaseVehicleValue | Vehicle type lookup table (see 6.1).                                   |
| AlignmentBonus   | 0–15 points. Calculated via DotProduct of LookVectors at confirmation. |
| EventMultiplier  | 0 by default. Set by active server event (e.g., Concert = 0.5).        |
| Penalties        | Accumulated from tip-overs, trap damage, Supercar collisions.          |

### 6.3 Spawn Rate Weighting

Default traffic composition per spawn tick:

| Vehicle     | Spawn Weight |
| :---------- | :----------- |
| Scooter     | 45%          |
| Sport Bike  | 25%          |
| Family Car  | 18%          |
| Aggro SUV   | 10%          |
| VIP Supercar| 2%           |

Flash Mob event overrides to 95% Scooter / 5% Sport Bike for its 10-second burst.

---

## 7. Map & Zone Design

### 7.1 Map Structure

Single continuous street map. One canonical map at launch (v1.0). Higher-tier maps unlocked via meta-progression (post-launch).

**Street Layout:**
```
[Traffic Spawn Node] → [Main Street Lane] → [Traffic Despawn Node]
                                ↑
                    [Parking Lots: Left & Right Side]
                    [Hiding Volumes: Alley entrances, shop doorways]
                    [Shop (In-Match)]
                    [Bank Terminal]
```

### 7.2 Parking Lot Zones

- Each player is assigned one zone upon joining.
- Zones are fixed grid areas marked visually with paint on the ground.
- Zone size scales with server player count to prevent overcrowding (fewer players = larger zones).
- A player can only park vehicles in their own zone. Vehicles parked in another player's zone are auto-ejected after 5 seconds and flagged as trespassing.

**Zone Ownership:**
- Zones cannot be permanently stolen. They are assigned per session.
- A player whose zone is full may temporarily overflow into neutral "overflow" zones at the map edges.

### 7.3 Hiding Volumes

- Scattered at 4–6 fixed positions (alley entrances, shop interiors, food stall overhangs).
- Block Police NPC sightline raycasts.
- Player inside a `HidingVolume` cannot whistle or dash (too concealed to work).

### 7.4 Bank Terminal

- Fixed position kiosk in the map.
- Player must physically walk to it to bank (deposit) their current unbanked shift currency.
- Banked currency is safe from Raid event penalties.
- Unbanked currency is lost entirely if the player disconnects mid-session.

### 7.5 In-Match Shop

- Fixed position vendor NPC.
- Sells consumables: Spike Strips, Energy Drinks, Bribe Money.
- Prices paid in current unbanked shift currency.

---

## 8. Progression System

### 8.1 Skill Tree

Unlocked by spending banked earnings at the inter-session upgrade screen. Three branches.

**Branch 1: Hustle (Speed / Stamina)**

| Node            | Cost  | Effect                          |
| :-------------- | :---- | :------------------------------ |
| Quick Feet I    | 500   | WalkSpeed +2                    |
| Quick Feet II   | 1200  | WalkSpeed +2                    |
| Quick Feet III  | 2500  | WalkSpeed +2                    |
| Iron Lungs I    | 800   | Stamina Pool +30                |
| Iron Lungs II   | 1800  | Stamina Pool +30                |

**Branch 2: Dominance (Strength / PvP)**

| Node            | Cost  | Effect                                         |
| :-------------- | :---- | :--------------------------------------------- |
| Heavy Hands I   | 600   | Dash knockback force +25%                      |
| Heavy Hands II  | 1500  | Melee interrupt duration +0.3s                 |
| Intimidation    | 3000  | Players ragdolled by you stay down 0.3s longer |

**Branch 3: Territory (Whistle / Economy)**

| Node            | Cost  | Effect                                               |
| :-------------- | :---- | :--------------------------------------------------- |
| Loud Whistle I  | 500   | Whistle Radius +3 studs                              |
| Loud Whistle II | 1200  | Whistle Radius +3 studs                              |
| Loud Whistle III| 2500  | Whistle Radius +4 studs                              |
| Grid Eye        | 1000  | AlignmentBonus tolerance loosened (DotProduct ≥ 0.95)|
| Sharp Eye       | 2000  | Helmet Thief detection range shown on HUD            |

### 8.2 Syndicates (Guilds)

- Unlocked after 10 sessions played.
- Up to 8 players per Syndicate.
- Syndicate members on the same server share a soft "turf" bonus: +5% payout when parking in adjacent zones.
- Syndicate leaderboard tracked globally. Top 3 Syndicates per week earn cosmetic banner rewards.

### 8.3 Titles & Badges

Displayed under player username. Earned by milestone conditions.

| Title               | Condition                                        |
| :------------------ | :----------------------------------------------- |
| Parkir Pemula       | Complete first session.                          |
| Tukang Parkir       | Bank 10,000 total earnings.                      |
| Raja Parkir         | Bank 100,000 total earnings.                     |
| Bos Parkir          | Reach max level in all 3 Skill Tree branches.    |
| Pencuri Gagal       | Knock out 50 Helmet Thieves.                     |
| Tukang Onar         | Successfully tackle 100 rival players.           |

---

## 9. Economy Design

### 9.1 Currency Types

| Currency         | Earned By                         | Lost By                                         | Used For                            |
| :--------------- | :-------------------------------- | :---------------------------------------------- | :---------------------------------- |
| Shift Currency   | Parking vehicles, AlignmentBonus  | Raid (20%), tip-over penalty, trap penalty      | In-match shop, banking              |
| Banked Earnings  | Banking Shift Currency at terminal| Skill Tree upgrades                             | Skill Tree, Syndicate contributions |
| Robux            | Real-money purchase               | N/A                                             | Gamepasses, cosmetics, consumables  |

### 9.2 Currency Sinks

- In-match shop (consumables).
- Skill Tree upgrades.
- Syndicate contribution pool (optional).

### 9.3 Economy Balance Goals

- A new player earning ~80–150 Shift Currency per session.
- First Skill Tree unlock achievable within 5–7 sessions.
- No single session should feel economically irrelevant (minimum floor payout guaranteed per vehicle).

---

## 10. Dynamic Events

`EventController` fires one event randomly every 3–7 minutes. Only one event active at a time.

### 10.1 Monsoon Rain

**Duration:** 90 seconds.

| Effect                          | Implementation                                               |
| :------------------------------ | :----------------------------------------------------------- |
| Ground friction reduced         | `Workspace.Terrain.WaterWaveSize` properties adjusted; all ground parts' `Friction` reduced via a server loop. |
| Vehicles slide further          | Physics naturally amplified by reduced friction.             |
| Player WalkSpeed −15%           | All `Humanoid.WalkSpeed` values multiplied by 0.85 for duration. |
| Visual: rain particles          | Server fires `UnreliableRemoteEvent` to all clients to enable rain `ParticleEmitter`. |

### 10.2 Satpol PP Raid

**Duration:** Until all spawned police NPCs are "resolved" (fled due to event timer, not defeated) or 120 seconds.

| Effect                              | Implementation                                                          |
| :---------------------------------- | :---------------------------------------------------------------------- |
| Police pursuit AI spawned           | 2–4 Satpol PP NPCs created at map edge spawn points.                    |
| Players must hide or lose currency  | See Section 5.3 for NPC behavior. `HidingVolume` parts block LoS raycasts. |
| Bribe Money consumable available    | If player uses it while being chased, police NPC targeting is cleared for that player. |

### 10.3 Flash Mob / Concert

**Duration:** 10-second injection burst. Vehicles persist until parked or despawned.

| Effect                              | Implementation                                                            |
| :---------------------------------- | :------------------------------------------------------------------------ |
| 30+ motorcycles injected            | `SpawnController` temporarily overrides spawn weight to 95% Scooter.     |
| Traffic lane overwhelmed            | Vehicles queue at entrance — some may collide and chain into each other.  |
| +50% payout multiplier              | `EventMultiplier = 0.5` applied to all payouts during event window.       |
| Increased Helmet Thief spawn chance | One additional Helmet Thief may spawn during the burst window.            |

---

## 11. Multiplayer Design

### 11.1 Server Composition

- Max 8 players per server.
- All players on the same server share the same map, traffic, and event stream.
- Zone assignment is first-come, first-served on join.

### 11.2 Player Interaction Modes

| Mode            | Description                                                                 |
| :-------------- | :-------------------------------------------------------------------------- |
| Competitive     | All players compete for the same vehicles. Direct PvP (tackle, strip) allowed. |
| Syndicate Ally  | Members share turf bonus but can still tackle each other (friendly sabotage). |

No pure cooperative mode in v1.0. Asymmetric competition is core to the experience.

### 11.3 Anti-Exploit Design

All gameplay-consequential inputs validated server-side:

| Input                      | Server Validation                                                         |
| :------------------------- | :------------------------------------------------------------------------ |
| Whistle                    | Rate limit: max 1 per 0.5s. Stamina state confirmed server-side.          |
| Dash direction             | Direction vector normalized server-side. Max 45° deviation from facing.   |
| Vehicle placement confirm  | Ownership check: player must own the lot. Position sanity check: within lot bounds. |
| Payout claim               | Vehicle must be in `Parked` state. Owner must match player ID.             |
| Consumable use             | Item ownership verified against server-side inventory before effect fires. |

---

## 12. UI & HUD Design

### 12.1 HUD Layout

```
┌────────────────────────────────────────────────────────┐
│              [SHIFT TRACKER: 08:42 | 💰 340]           │  ← Top Center
│  ◄ [Threat Arrow]                   [Threat Arrow] ►   │  ← Screen Edges
│                                                        │
│                                                        │
│                   [GAME WORLD]                         │
│                                                        │
│         [TUG-OF-WAR BAR] (contextual, above head)     │
│                                                        │
│  [STAMINA BAR]                          [MINI MAP]     │  ← Bottom
│  [Action: WHISTLE | DASH | SMACK | PLACE]              │  ← Bottom
└────────────────────────────────────────────────────────┘
```

### 12.2 HUD Elements

**Shift Tracker**
- Position: Top center.
- Content: Session countdown timer + current unbanked currency (in-flight) + banked currency (locked).
- Banked amount turns green when updated. Unbanked amount pulses red during Raid event.

**Threat Indicators**
- Position: Screen edges, directional.
- Appear as red pulsing arrows pointing toward any Helmet Thief inside the player's zone.
- Opacity scales with proximity of threat.

**Stamina Bar**
- Position: Bottom left.
- Depletes on whistle (slow drain) and dash (instant chunk).
- Color shifts yellow → red as it depletes.

**Tug-of-War Bar**
- Position: Above the player's own character head (world-space, facing camera).
- Shown only during active TugOfWar state.
- Divided bar filling from center outward — left = rival claim, right = player claim.
- Shakes and flashes when a side reaches full.

**Spatial Grid Overlay**
- Position: Ground plane, within player's parking lot zone.
- Appears only when player enters Drag Mode.
- Semi-transparent white grid with snapping indicators.
- Togglable in Settings.

**Mobile-Specific:**
- Virtual D-pad: Bottom left.
- Action buttons (Whistle, Dash, Smack, Interact): Bottom right, thumb-reachable.
- All touch targets minimum 44×44 pixel equivalent.

### 12.3 Feedback Indicators

| Event                       | Visual Feedback                         | Audio Feedback             |
| :-------------------------- | :-------------------------------------- | :------------------------- |
| Payout collected            | Floating "+[amount]" text, gold color   | "Kaching!" SFX             |
| Tip-over penalty            | Red floating "−[amount]"                | Crash SFX                  |
| Tackle connects             | Screen shake (hit player's camera)      | Impact SFX                 |
| Ragdoll starts              | Screen tint red flash                   | Grunt SFX                  |
| Helmet Thief nearby         | Threat arrow + edge pulse               | Rustling/zipper 3D SFX     |
| Tug-of-War win              | Bar flashes green, "GRABBED!" text      | Victory sting SFX          |
| Raid event start            | Full-screen red overlay flash           | Siren SFX                  |

---

## 13. Art Direction

### 13.1 Visual Style

"Stylized Urban" — Indonesian street aesthetic, low-poly geometry, vibrant saturated texture palette. Prioritize performance; mobile must sustain 30fps.

**Color Palette:**
- Environment base: warm tawny asphalt, cream-yellow walls, rust-orange rooftops.
- Accent / neon: electric blue, hot pink, lime green (signage and UI elements).
- Player VFX: distinct per-player whistle color (pulled from a predefined palette of 8 hues).

### 13.2 Environment Props

| Prop Category      | Examples                                                              |
| :----------------- | :-------------------------------------------------------------------- |
| Street food        | Satay cart, martabak stand, es teh bucket.                            |
| Signage            | Hand-painted "PARKIR" boards, neon karaoke signs, warung banners.     |
| Clutter            | Cardboard boxes, plastic chairs, gas canisters, potted plants.        |
| Infrastructure     | Cracked asphalt decals, faded road markings, utility poles, puddles.  |

### 13.3 Character Design

- Player character: generic humanoid Roblox rig with customizable vest overlay.
- Vest is the primary cosmetic slot. Reads clearly at low polygon count.
- NPC Helmet Thieves: shifty humanoid rig, hoodie + beanie, exaggerated "sneaky" idle animation.
- Satpol PP: olive-green uniform, clearly readable silhouette distinct from players.

### 13.4 Vehicle Models

- Low-poly but recognizable silhouettes. Motorcycles must be distinguishable from each other at a glance from 15+ studs distance.
- VIP Supercar has a subtle gold sparkle particle permanently attached — signals high-value status.

---

## 14. Audio Design

### 14.1 Layers

| Layer      | Description                                                                 |
| :--------- | :-------------------------------------------------------------------------- |
| Ambient    | Looping street traffic hum. Crowd murmur. Distant music from a warung.      |
| Diegetic   | Whistle blows (per-player pitch), vehicle engine sounds, footsteps.         |
| Event      | Rain ambience (Monsoon). Siren wail (Raid). Crowd chanting (Flash Mob).     |
| Feedback   | UI sounds: coin, penalty, hit, ragdoll, confirmation.                       |

### 14.2 3D Spatial Audio

- Helmet Thief rummaging sound uses `RollOffMode = InverseTapered`. Audible radius ~20 studs. Maximum intensity at <3 studs.
- Guides player toward threat without requiring HUD awareness — allows eyes-free spatial search.

### 14.3 Per-Player Whistle Pitch

- On player join, server assigns a unique pitch from a set of 8 semitones (C4 through C5).
- All clients receive this assignment via a `RemoteEvent` and apply the corresponding pitch to whistle SFX.
- Allows players in a chaotic multi-whistle moment to identify "that's my whistle" by ear.

---

## 15. Monetization Design

All monetization is purely cosmetic or convenience — no mechanics locked behind a paywall that cannot be reached through gameplay.

### 15.1 Gamepasses (Permanent Unlock)

| Pass         | Price (Robux) | Effect                                                       | Design Note                                             |
| :----------- | :------------ | :----------------------------------------------------------- | :------------------------------------------------------ |
| VIP Whistle  | 299           | +20% base aggro radius. Whistle VFX becomes gold.            | Provides real advantage but not game-breaking vs. Skill Tree node equivalence. |
| Landlord     | 499           | +1 premium parking slot per map tier.                        | Economic advantage. Justified for dedicated players.    |

### 15.2 Developer Products (Consumable)

| Product      | Price (Robux) | Effect                                              |
| :----------- | :------------ | :-------------------------------------------------- |
| Energy Drink | 25            | Instantly refills stamina bar.                      |
| Bribe Money  | 35            | Clears Police NPC targeting on self during Raid.    |

Both items are also available via in-match shop with Shift Currency, ensuring F2P access.

### 15.3 Cosmetics

**Vests (Direct Purchase / Lootbox):**
- Neon Construction, Leather Jacket, Cyberpunk UI, Gold Foil, Street Camo.
- Price range: 50–150 Robux direct. Lootbox: 75 Robux per roll.

**Whistle Sounds:**
- Train Horn, Airhorn, Duck Quack, Vuvuzela, Referee Whistle.
- 80 Robux each.

**Trails:**
- Walk and dash trail effects (smoke, sparks, coin shower, neon line).
- 60–120 Robux each.

---

## 16. Session Structure

### 16.1 A Single Shift (One Session)

| Phase          | Duration    | Description                                                                 |
| :------------- | :---------- | :-------------------------------------------------------------------------- |
| Warm-Up        | 0–60s       | Traffic spawns at reduced rate. Players learn zone layout.                  |
| Peak Shift     | 1m–8m       | Full spawn rate. Dynamic events can start firing from 3m mark.              |
| Rush Hour      | 8m–10m      | Spawn rate increases by 20%. Final event may fire.                          |
| Shift End      | 10:00       | All new traffic stopped. Players have 30 seconds to clear in-progress parks.|
| Payout Screen  | Post-session | Shift summary: total earned, banked, penalties, top earner callout.         |

### 16.2 Inter-Session

- Players return to a Lobby area.
- Skill Tree upgrade screen available.
- Consumable loadout management.
- Leaderboard display (top earners this shift, Syndicate standings).
- New session begins when 3+ players ready up or a 60-second auto-start timer expires.

---

*Document version 1.0. Subject to revision as playtesting data is collected.*
