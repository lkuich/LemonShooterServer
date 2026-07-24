extends RefCounted

const PERKS := {
	"sleight_of_hand": "Sleight of Hand",
	"juggernog": "Juggernog",
	"featherfoot": "Featherfoot",
	"stopping_power": "Stopping Power",
	"scavenger": "Scavenger",
	"quick_fix": "Quick Fix",
	"last_stand": "Last Stand",
	"demolitionist": "Demolitionist",
	"shockwave_ground_pound": "Shockwave Ground Pound"
}


static func random_unowned(active_perks: Array) -> Dictionary:
	var available: Array[String] = []
	for perk_id in PERKS:
		if perk_id not in active_perks:
			available.append(perk_id)
	if available.is_empty():
		return {}
	var selected: String = available.pick_random()
	return {"id": selected, "name": str(PERKS[selected])}


static func random_perk() -> Dictionary:
	return random_unowned([])


static func name_for(perk_id: String) -> String:
	return str(PERKS.get(perk_id, perk_id.replace("_", " ").capitalize()))
