extends Node
## City treasury. Phase 2 only needs a balance that construction spends from
## and demolition refunds into; budgets, taxes and loans arrive in Phase 4.

var balance: int = 0


func _ready() -> void:
	balance = GameData.integer("economy/start_money")


func can_afford(amount: int) -> bool:
	return amount <= balance


## Spends if affordable; returns false (and changes nothing) otherwise.
func try_spend(amount: int) -> bool:
	if amount > balance:
		return false
	balance -= amount
	EventBus.money_changed.emit(balance)
	return true


func refund(amount: int) -> void:
	balance += amount
	EventBus.money_changed.emit(balance)
