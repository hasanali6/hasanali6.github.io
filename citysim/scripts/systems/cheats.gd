extends Node
## Sandbox options (autoload, Ayarlar → Hileler), stored in user://settings.cfg:
##   unlimited_money : the treasury never drops below a million
##   fast_growth     : three times the newcomers, growth and level-ups
##   densify         : thriving houses and shops are rebuilt denser over time
##                     (house -> apartment block -> tower); on by default
## Plus one-off buttons: add money, open every milestone.

const SECTION := "cheats"
const FLOOR := 1000000

var unlimited_money: bool = false
var fast_growth: bool = false
var densify: bool = true

var _timer: float = 0.0


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(GraphicsSettings.SETTINGS_PATH) == OK:
		unlimited_money = bool(cfg.get_value(SECTION, "unlimited_money", false))
		fast_growth = bool(cfg.get_value(SECTION, "fast_growth", false))
		densify = bool(cfg.get_value(SECTION, "densify", true))


func _process(delta: float) -> void:
	_timer += delta
	if _timer < 1.0:
		return
	_timer = 0.0
	if unlimited_money and EconomySystem.balance < FLOOR:
		EconomySystem.cheat_money(FLOOR * 2 - EconomySystem.balance)


func growth_factor() -> float:
	return 3.0 if fast_growth else 1.0


func set_option(key: String, on: bool) -> void:
	set(key, on)
	var cfg := ConfigFile.new()
	cfg.load(GraphicsSettings.SETTINGS_PATH)
	cfg.set_value(SECTION, key, on)
	cfg.save(GraphicsSettings.SETTINGS_PATH)


func add_money(amount: int) -> void:
	EconomySystem.cheat_money(amount)
	EventBus.sfx_requested.emit("coin")
