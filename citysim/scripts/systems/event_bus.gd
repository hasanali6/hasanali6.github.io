extends Node
## Central signal hub. Systems never hold references to each other; they emit
## and listen here so any module can be removed or run headless on its own.

# --- Simulation time ---
signal sim_tick(tick_index: int)
signal month_changed(month_index: int)
signal speed_changed(speed_index: int)
signal time_jumped(hour: float)

# --- Camera gestures (screen space, produced by InputController) ---
signal pan_requested(screen_delta: Vector2)
signal pan_released(screen_velocity: Vector2)
signal zoom_requested(factor: float, screen_center: Vector2)
signal rotate_requested(angle_rad: float)
signal tilt_requested(screen_delta_y: float)
signal tapped(screen_pos: Vector2)
signal long_pressed(screen_pos: Vector2)

# --- Build tools ---
## Single-finger stroke while a tool captures input (GestureTracker.Pointer phase).
signal tool_pointer(phase: int, screen_pos: Vector2)
## Tool or tool option chosen in the UI. tool == "" means no tool.
signal build_tool_selected(tool: String, options: Dictionary)
## Live info about the stroke in progress: {active, valid, cost, length, error, screen_pos}.
signal road_preview_changed(info: Dictionary)
signal roads_changed()

# --- Zoning and buildings ---
## Zoning cells were regenerated after a road edit (indices changed).
signal zone_cells_rebuilt()
signal zones_changed()
signal buildings_changed()
## Info about a building the player long-pressed: {zone_key, level, floors, width, depth}.
signal building_inspected(info: Dictionary)

# --- Economy ---
signal money_changed(balance: int)
signal company_closed(building_id: int)
signal company_bankrupt(building_id: int)
signal workers_laid_off(building_id: int, level: int, count: int)
signal shops_changed()
signal citizens_reported(report: Dictionary)
signal companies_reported(report: Dictionary)
## Monthly books closed: {income: {...}, expenses: {...}, net}.
signal budget_settled(ledger: Dictionary)
signal road_upkeep_changed(per_month: float)
## RCI demand per zone group in -1..1.
signal demand_changed(demand: Dictionary)
## Periodic city statistics for the UI (population, happiness, jobs...).
signal city_stats_changed(stats: Dictionary)
signal taxes_changed()
signal loan_changed()

# --- Services and utilities ---
## Service budget or utility fee slider moved.
signal service_budgets_changed()
## Coverage, utilities and pollution were recomputed (building fields updated).
signal services_changed()
## Monthly service books: {upkeep: {category: amount}, fees: {power, water}, ...}.
signal services_reported(report: Dictionary)
## Info overlay chosen in the UI ("" = off).
signal overlay_selected(key: String)

# --- Traffic ---
## Driving lanes were rebuilt after a road edit (vehicles remap their pieces).
signal lanes_rebuilt()
## A traffic assignment finished: congestion, routes and commute times changed.
signal traffic_updated()
## A road was long-pressed: {type_key, lanes, daily, ratio, speed_kmh}.
signal road_inspected(info: Dictionary)
## Mode choice of the latest demand round: {parking, riders, raw} (per day).
signal mobility_reported(report: Dictionary)

# --- Transit and districts ---
signal transit_changed()
## Line being drawn: {type, stops, cost, error}.
signal transit_draft_changed(info: Dictionary)
## Monthly transit books: {tickets, upkeep}.
signal transit_reported(report: Dictionary)
signal districts_changed()
## District being drawn: {points, error}.
signal district_draft_changed(info: Dictionary)
## Monthly district books: {recycling}.
signal district_reported(report: Dictionary)

# --- Progression, weather, saves ---
## A population milestone was reached: {name_key, reward, unlocks}.
signal milestone_reached(level: int, info: Dictionary)
## The milestone level changed (also after loading): locks and area follow.
signal progression_changed()
## Weather or season changed: {state, season, rain, snow, clouds, autumn}.
signal weather_changed(info: Dictionary)
signal saves_changed()

# --- World queries resolved by the camera ---
signal ground_long_pressed(world_pos: Vector3)

# --- Settings / UI ---
signal graphics_preset_changed(preset: String)
signal grid_overlay_toggled(enabled: bool)
signal notification_posted(category: String, text: String)
