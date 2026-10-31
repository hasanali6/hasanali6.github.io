class_name RoadTypes
extends RefCounted
## Cross-section maths for a road type entry from data/roads.json.
## Offsets are measured from the road centre line along the LEFT normal
## (positive = left of the travel direction a -> b). Traffic drives on the right.


static func lane_count(t: Dictionary) -> int:
	return int(t["lanes_per_dir"]) * (1 if bool(t["oneway"]) else 2)


## Carriageway width between the curbs (lanes + median).
static func carriageway_width(t: Dictionary) -> float:
	return lane_count(t) * float(t["lane_width_m"]) + float(t["median_width_m"])


static func total_width(t: Dictionary) -> float:
	return carriageway_width(t) + 2.0 * float(t["sidewalk_width_m"])


static func half_width(t: Dictionary) -> float:
	return total_width(t) * 0.5


## Lanes as [{offset, forward}], forward = travels from node a to node b.
static func lanes(t: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var w := float(t["lane_width_m"])
	var per_dir := int(t["lanes_per_dir"])
	if bool(t["oneway"]):
		var left_edge := carriageway_width(t) * 0.5
		for i in per_dir:
			out.append({"offset": left_edge - w * (i + 0.5), "forward": true})
	else:
		var half_median := float(t["median_width_m"]) * 0.5
		for i in per_dir:
			out.append({"offset": -(half_median + w * (i + 0.5)), "forward": true})
			out.append({"offset": half_median + w * (i + 0.5), "forward": false})
	return out
