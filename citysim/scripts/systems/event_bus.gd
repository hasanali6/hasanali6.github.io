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

# --- Economy ---
signal money_changed(balance: int)

# --- World queries resolved by the camera ---
signal ground_long_pressed(world_pos: Vector3)

# --- Settings / UI ---
signal graphics_preset_changed(preset: String)
signal grid_overlay_toggled(enabled: bool)
signal notification_posted(category: String, text: String)
