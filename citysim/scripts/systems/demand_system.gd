extends Node
## RCI demand. Every few ticks gathers city statistics from the citizen and
## company systems, turns them into demand per zone group (EconomyRules.demand),
## smooths it and broadcasts it. Building growth and immigration follow it;
## the HUD shows it as the four demand bars.

@export var citizen_system_path: NodePath
@export var company_system_path: NodePath

var demand: Dictionary = {"residential": 0.0, "migration": 0.0, "commercial": 0.0, "office": 0.0, "industrial": 0.0}
var stats: Dictionary = {}

var _citizens: Node
var _companies: Node
var _cfg: Dictionary
var _default_tax: float
var _tick: int = 0


func _ready() -> void:
	_citizens = get_node(citizen_system_path)
	_companies = get_node(company_system_path)
	_cfg = GameData.section("economy/demand")
	_default_tax = GameData.num("economy/taxes/default")
	EventBus.sim_tick.connect(_on_tick)
	EventBus.taxes_changed.connect(_update)
	_update.call_deferred()


func _on_tick(_t: int) -> void:
	_tick += 1
	if _tick % int(_cfg["update_ticks"]) == 0:
		_update()


func _update() -> void:
	stats = _citizens.stats()
	stats.merge(_companies.stats(), true)
	stats["goods_unmet_ratio"] = minf(float(stats["goods_unmet_ratio"]) + float(stats["goods_overflow_ratio"]), 1.0)
	var target := EconomyRules.demand(stats, EconomySystem.taxes, _cfg, _default_tax)
	var k := float(_cfg["smoothing"])
	for group: String in target:
		demand[group] = lerpf(float(demand[group]), float(target[group]), k)
	EventBus.demand_changed.emit(demand)
	EventBus.city_stats_changed.emit(stats)


func save_state() -> Dictionary:
	return {"demand": demand}


func load_state(state: Dictionary) -> void:
	for group: String in state.get("demand", {}):
		demand[group] = float(state["demand"][group])
