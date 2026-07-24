extends RefCounted

## Shared landing-impact tuning for players and physically simulated NPCs.
## 7.5 m/s is roughly the impact from a 3 m fall; severe multi-storey falls
## quickly become lethal instead of scaling gently forever.
const SAFE_LANDING_SPEED := 7.5
const LINEAR_DAMAGE_PER_SPEED := 5.5
const QUADRATIC_DAMAGE_PER_SPEED := 0.35


static func calculate(landing_speed: float) -> float:
	var excess_speed := maxf(landing_speed - SAFE_LANDING_SPEED, 0.0)
	return excess_speed * LINEAR_DAMAGE_PER_SPEED + excess_speed * excess_speed * QUADRATIC_DAMAGE_PER_SPEED
