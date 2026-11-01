class_name ProductRules
extends RefCounted
## Product types of the production chain (data/resources.json "products"):
## each factory makes one product (food, wood products, metal goods, fuel)
## from its own raw material (farm, forest, ore, oil). New factories pick
## the product whose raw material the city has most left over, so a farming
## town grows food factories and a mining town metal works.


## Product for every factory: existing choices are kept, new ones (empty or
## unknown) go to the product with the largest local raw surplus left after
## the factories already assigned. units: bid -> monthly units.
static func assign(units: Dictionary, current: Dictionary, raw_by_type: Dictionary, products: Dictionary,
		raw_per_good: float) -> Dictionary:
	var out := {}
	var need := {}
	for p: String in products:
		need[p] = 0.0
	var ids := units.keys()
	ids.sort()
	for bid: int in ids:
		var p := str(current.get(bid, ""))
		if products.has(p):
			out[bid] = p
			need[p] += float(units[bid]) * raw_per_good
	var keys := products.keys()
	keys.sort()
	for bid: int in ids:
		if out.has(bid):
			continue
		var best := str(keys[bid % keys.size()])
		var best_left := -INF
		for p: String in keys:
			var left := float(raw_by_type.get(products[p]["raw"], 0.0)) - float(need[p])
			if left > best_left + 0.01:
				best_left = left
				best = p
		out[bid] = best
		need[best] += float(units[bid]) * raw_per_good
	return out


## Raw material use per product: need, local (the city's own raw of that
## type first), share of the need covered locally, and for each raw type the
## share of its output used in the city (the rest is exported).
static func balance(made: Dictionary, raw_by_type: Dictionary, products: Dictionary, raw_per_good: float) -> Dictionary:
	var per_product := {}
	var used_by_raw := {}
	for p: String in products:
		var raw := str(products[p]["raw"])
		var need := float(made.get(p, 0.0)) * raw_per_good
		var local := minf(float(raw_by_type.get(raw, 0.0)), need)
		per_product[p] = {"units": float(made.get(p, 0.0)), "need": need, "local": local,
			"share": 0.0 if need <= 0.0 else local / need}
		used_by_raw[raw] = float(used_by_raw.get(raw, 0.0)) + local
	var raw_share := {}
	for raw: String in raw_by_type:
		var produced := float(raw_by_type[raw])
		raw_share[raw] = 0.0 if produced <= 0.0 else clampf(float(used_by_raw.get(raw, 0.0)) / produced, 0.0, 1.0)
	return {"products": per_product, "raw_share": raw_share}
