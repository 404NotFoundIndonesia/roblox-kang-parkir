-- Luau type definitions shared across server and client.
-- Import: local Types = require(path); type Foo = Types.Foo

export type SkillTreeData = {
	WhistleLevel  : number, -- 0–3
	StrengthLevel : number, -- 0–3
	SpeedLevel    : number, -- 0–3
	StaminaLevel  : number, -- 0–3
}

export type StatsData = {
	ThievesInterrupted : number,
	RivalsRagdolled    : number,
	TotalParked        : number,
}

export type PlayerData = {
	BankedEarnings   : number,
	SkillTree        : SkillTreeData,
	OwnedCosmetics   : { string },
	OwnedGamepasses  : { string },
	TotalSessions    : number,
	Stats            : StatsData,
	SchemaVersion    : number,
}

export type VehicleState = "Traffic" | "Aggroed" | "AtEntrance" | "Dragging" | "Parked" | "Damaged" | "Departing"

export type PlayerActionState = "Idle" | "Whistling" | "Dragging" | "Dashing" | "Ragdoll" | "Hiding" | "Stunned"

export type EventType = "MonsoonRain" | "SatpolRaid" | "FlashMob"

export type NPCState = "Roam" | "Navigate" | "Interact" | "Flee" | "Ragdoll" | "Despawn"

export type SessionPhase = "Lobby" | "WarmUp" | "PeakShift" | "RushHour" | "ShiftEnd" | "PostSession"

return {}
