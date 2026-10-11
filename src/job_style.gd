extends RefCounted
## Stable task identities shared by the job card and the construction site.
## Numbers and words accompany each colour, so colour is never the only cue.
const COLORS := [Color("#df3f9b"), Color("#2379d5"), Color("#00a58a"), Color("#7954dc"), Color("#e45e36")]
const SHORT_NAMES := ["JUNK", "DIG", "POUR", "STACK", "PUR"]

static func title(step: int, label: String = "") -> String:
	return "%d %s" % [step + 1, SHORT_NAMES[step] if label.is_empty() else label]
