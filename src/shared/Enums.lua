-- Runtime mirrors of Types.lua string unions. Use Enums.X.Y instead of spelling literal strings.
local Enums = table.freeze({
	VehicleState = table.freeze({
		Traffic    = "Traffic",
		Aggroed    = "Aggroed",
		AtEntrance = "AtEntrance",
		Dragging   = "Dragging",
		Parked     = "Parked",
		Damaged    = "Damaged",
		Departing  = "Departing",
	}),

	PlayerActionState = table.freeze({
		Idle      = "Idle",
		Whistling = "Whistling",
		Dragging  = "Dragging",
		Dashing   = "Dashing",
		Ragdoll   = "Ragdoll",
		Hiding    = "Hiding",
		Stunned   = "Stunned",
	}),

	EventType = table.freeze({
		MonsoonRain = "MonsoonRain",
		SatpolRaid  = "SatpolRaid",
		FlashMob    = "FlashMob",
	}),

	NPCState = table.freeze({
		Roam     = "Roam",
		Navigate = "Navigate",
		Interact = "Interact",
		Flee     = "Flee",
		Ragdoll  = "Ragdoll",
		Despawn  = "Despawn",
	}),

	SessionPhase = table.freeze({
		Lobby       = "Lobby",
		WarmUp      = "WarmUp",
		PeakShift   = "PeakShift",
		RushHour    = "RushHour",
		ShiftEnd    = "ShiftEnd",
		PostSession = "PostSession",
	}),
})

return Enums
