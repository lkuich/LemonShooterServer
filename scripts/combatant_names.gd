extends RefCounted

const FEATURED_NAMES := [
	"MasticShark", "DonatelloPrime", "GlizzyGobbler", "TacticalWaffle",
	"CrustyWizard", "TurboPickle", "SneakyBiscuit", "ProfessorPants"
]

const FIRST_WORDS := [
	"Mastic", "Donatello", "Glizzy", "Tactical", "Waffle", "Crusty", "Turbo", "Sneaky",
	"Beefy", "Feral", "Goblin", "Nacho", "Pickle", "Biscuit", "Quantum", "Uncle",
	"Professor", "Captain", "Doctor", "Sir", "Mega", "Dumpster", "Banana", "Cheese",
	"Noodle", "Potato", "Soggy", "Disco", "Spicy", "Chunky", "Cosmic", "Rogue",
	"Certified", "Suspicious", "Aggressive", "Emotional", "Nuclear", "Caffeinated", "Boneless", "Interstellar"
]

const SECOND_WORDS := [
	"Shark", "Prime", "Gobbler", "Wizard", "Bandit", "Gremlin", "Cannon", "Wrangler",
	"Nugget", "Crusader", "Goblin", "Phantom", "Toaster", "Enjoyer", "Destroyer", "Machine",
	"Pants", "Missile", "Warden", "Mancer", "Lord", "Socks", "Pickle", "Burrito",
	"Menace", "Muffin", "Hammer", "Goose", "Raccoon", "Badger", "Sprinkler", "Lasagna",
	"Prophet", "Tornado", "Sasquatch", "Pancake", "Mechanic", "Diplomat", "Warlock", "Sandwich"
]


static func random_unique(used_names: Dictionary = {}) -> String:
	var chosen := ""
	for _attempt in 128:
		var candidate: String
		if randf() < 0.16:
			candidate = FEATURED_NAMES.pick_random()
		else:
			candidate = "%s%s" % [FIRST_WORDS.pick_random(), SECOND_WORDS.pick_random()]
		if not used_names.has(candidate.to_lower()):
			chosen = candidate
			break
	if chosen.is_empty():
		chosen = "%s%s" % [FIRST_WORDS.pick_random(), SECOND_WORDS.pick_random()]
		var suffix := 2
		while used_names.has((chosen + str(suffix)).to_lower()):
			suffix += 1
		chosen += str(suffix)
	used_names[chosen.to_lower()] = true
	return chosen


static func used_name_set(names: Array) -> Dictionary:
	var result := {}
	for value in names:
		result[str(value).to_lower()] = true
	return result
