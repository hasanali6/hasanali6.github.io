extends Node
## City treasury and budget.
##  * Construction spends immediately; demolition refunds.
##  * Each month the books close: residential tax (by education level) and
##    company taxes (by zone group) come in with the shrinking early-game
##    state subsidy; road upkeep and the loan instalment go out.
##  * One adjustable loan: borrowing more pays cash out, borrowing less repays
##    from the treasury. Its limit grows with population; the interest rate
##    grows with how much of the limit is used.
## Settlement runs deferred on month change, after the citizen and company
## systems have filed their monthly reports.

var balance: int = 0
var taxes: Dictionary = {}                     # group -> percent
var residential_by_edu := PackedFloat32Array()  # education level -> percent
var loan: float = 0.0
var loan_rate: float = 0.0
var loan_payment: float = 0.0
var loan_months_left: int = 0
var last_ledger: Dictionary = {}

var _tax_cfg: Dictionary
var _budget_cfg: Dictionary
var _loan_cfg: Dictionary
var _population: int = 0
var _road_upkeep: float = 0.0
var _construction: float = 0.0
var _refunds: float = 0.0
var _citizens: Dictionary = {}
var _companies: Dictionary = {}


func _ready() -> void:
	_tax_cfg = GameData.section("economy/taxes")
	_budget_cfg = GameData.section("economy/budget")
	_loan_cfg = GameData.section("economy/loan")
	reset_state()
	EventBus.month_changed.connect(func(_m: int) -> void: _settle.call_deferred())
	EventBus.citizens_reported.connect(func(r: Dictionary) -> void: _citizens = r)
	EventBus.companies_reported.connect(func(r: Dictionary) -> void: _companies = r)
	EventBus.road_upkeep_changed.connect(func(v: float) -> void: _road_upkeep = v)
	EventBus.city_stats_changed.connect(func(s: Dictionary) -> void: _population = int(s.get("population", 0)))


# --- Treasury ---------------------------------------------------------------------

func can_afford(amount: int) -> bool:
	return amount <= balance


## Spends if affordable; returns false (and changes nothing) otherwise.
func try_spend(amount: int) -> bool:
	if amount > balance:
		return false
	balance -= amount
	_construction += amount
	EventBus.money_changed.emit(balance)
	return true


func refund(amount: int) -> void:
	balance += amount
	_refunds += amount
	EventBus.money_changed.emit(balance)


# --- Taxes ---------------------------------------------------------------------------

func tax_rate(group: String) -> float:
	return float(taxes.get(group, _tax_cfg["default"]))


## Share of the taxed amount that goes to the city (the rest is national tax).
func city_share() -> float:
	return float(_tax_cfg["city_share"])


## Residential tax depends on the earner's education; the group slider shifts all levels.
func residential_rate(education: int) -> float:
	return residential_by_edu[clampi(education, 0, residential_by_edu.size() - 1)]


func set_tax(group: String, percent: float) -> void:
	var value := clampf(roundf(percent), float(_tax_cfg["min"]), float(_tax_cfg["max"]))
	if group == "residential":
		var delta := value - float(taxes["residential"])
		for e in residential_by_edu.size():
			residential_by_edu[e] = clampf(residential_by_edu[e] + delta, float(_tax_cfg["min"]), float(_tax_cfg["max"]))
	taxes[group] = value
	EventBus.taxes_changed.emit()


func set_residential_edu_tax(education: int, percent: float) -> void:
	residential_by_edu[education] = clampf(roundf(percent), float(_tax_cfg["min"]), float(_tax_cfg["max"]))
	EventBus.taxes_changed.emit()


# --- Loan ------------------------------------------------------------------------------

func loan_limit() -> int:
	return EconomyRules.loan_limit(_population, _loan_cfg)


## Sets the outstanding loan to `amount` (rounded to the step). Taking more
## pays cash out; taking less repays from the treasury if it can afford it.
func set_loan(amount: float) -> bool:
	var step := float(_loan_cfg["step"])
	var target := clampf(roundf(amount / step) * step, 0.0, float(loan_limit()))
	var delta := target - loan
	if delta < 0.0 and -delta > balance:
		return false
	balance += int(delta)
	loan = target
	loan_rate = EconomyRules.loan_interest(loan, loan_limit(), _loan_cfg)
	loan_months_left = int(_loan_cfg["term_months"]) if loan > 0.0 else 0
	loan_payment = EconomyRules.loan_payment(loan, loan_rate, loan_months_left)
	EventBus.money_changed.emit(balance)
	EventBus.loan_changed.emit()
	return true


# --- Monthly settlement --------------------------------------------------------------

func _settle() -> void:
	var company_taxes: Dictionary = _companies.get("taxes", {})
	var income := {
		"residential": float(_citizens.get("residential_tax", 0.0)),
		"commercial": float(company_taxes.get("commercial", 0.0)),
		"office": float(company_taxes.get("office", 0.0)),
		"industrial": float(company_taxes.get("industrial", 0.0)),
		"subsidy": EconomyRules.subsidy(_population, _budget_cfg),
	}
	var instalment := 0.0
	if loan > 0.0 and loan_months_left > 0:
		instalment = loan_payment
		var interest := loan * loan_rate / 12.0
		loan = maxf(loan - (instalment - interest), 0.0)
		loan_months_left -= 1
		if loan_months_left == 0 or loan < 1.0:
			loan = 0.0
			loan_payment = 0.0
		EventBus.loan_changed.emit()
	var expenses := {"roads": _road_upkeep, "loan": instalment}
	var total_in := 0.0
	for v: float in income.values():
		total_in += v
	var total_out := 0.0
	for v: float in expenses.values():
		total_out += v
	var net := total_in - total_out
	balance += roundi(net)
	last_ledger = {
		"income": income, "expenses": expenses, "net": net,
		"construction": _construction, "refunds": _refunds,
	}
	_construction = 0.0
	_refunds = 0.0
	EventBus.money_changed.emit(balance)
	EventBus.budget_settled.emit(last_ledger)


## Back to a fresh city's treasury, default taxes and no loan.
func reset_state() -> void:
	balance = GameData.integer("economy/start_money")
	taxes = {}
	for group: String in _tax_cfg["groups"]:
		taxes[group] = float(_tax_cfg["default"])
	residential_by_edu = PackedFloat32Array()
	for e in GameData.integer("economy/education_levels"):
		residential_by_edu.append(float(_tax_cfg["default"]))
	loan = 0.0
	loan_rate = 0.0
	loan_payment = 0.0
	loan_months_left = 0
	last_ledger = {}
	_construction = 0.0
	_refunds = 0.0
	_citizens = {}
	_companies = {}


func save_state() -> Dictionary:
	return {
		"balance": balance, "taxes": taxes, "residential_by_edu": residential_by_edu, "loan": loan,
		"loan_rate": loan_rate, "loan_payment": loan_payment, "loan_months_left": loan_months_left,
		"last_ledger": last_ledger,
	}


func load_state(state: Dictionary) -> void:
	balance = int(state.get("balance", balance))
	for key: String in state.get("taxes", {}):
		taxes[key] = float(state["taxes"][key])
	if state.has("residential_by_edu"):
		residential_by_edu = PackedFloat32Array(state["residential_by_edu"])
	loan = float(state.get("loan", 0.0))
	loan_rate = float(state.get("loan_rate", 0.0))
	loan_payment = float(state.get("loan_payment", 0.0))
	loan_months_left = int(state.get("loan_months_left", 0))
	last_ledger = state.get("last_ledger", {})
	EventBus.money_changed.emit(balance)
	EventBus.taxes_changed.emit()
	EventBus.loan_changed.emit()
