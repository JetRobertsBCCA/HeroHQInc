class_name TextFormat
extends RefCounted
## Small shared formatters. Neutral by construction: every title-specific word
## comes from the pack's locale, never from here.

static func amount(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


## 0:20, 2:30, 12:05 — compact so it fits a 360px-wide card.
static func duration(seconds: float) -> String:
	var total := maxi(int(roundf(seconds)), 0)
	return "%d:%02d" % [total / 60, total % 60]


## "+18 <unit>  +2 <unit>" in resource-id order.
static func rewards(pack: GamePack, rewards: Dictionary) -> String:
	var parts: Array[String] = []
	var ids: Array = rewards.keys()
	ids.sort()
	for raw_id in ids:
		var resource_id := str(raw_id)
		parts.append("+%s %s" % [
			amount(float(rewards[raw_id])),
			pack.label("resources.%s" % resource_id, resource_id),
		])
	return "  ".join(parts)
