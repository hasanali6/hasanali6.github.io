class_name HouseholdData
extends RefCounted
## Households stored as parallel packed arrays (structure of arrays) so tens
## of thousands can be simulated in GDScript. A household index stays valid
## while it lives; dead slots are reused through a free list.
## Each household has up to MAX_ADULTS working-age adults; per adult we keep
## an education level (0..2) and a job code (-1 = unemployed, otherwise
## company building id * 4 + job education level).

const MAX_ADULTS := 3
const NO_JOB := -1

var alive := PackedByteArray()
var home := PackedInt32Array()
var adults := PackedByteArray()
var children := PackedByteArray()
var seniors := PackedByteArray()
var edu := PackedByteArray()      # MAX_ADULTS per household
var job := PackedInt32Array()     # MAX_ADULTS per household
var money := PackedFloat32Array()
var happiness := PackedFloat32Array()
var broke := PackedByteArray()    # consecutive months with negative money
var income := PackedFloat32Array()

var count: int = 0
var _free := PackedInt32Array()


func capacity() -> int:
	return alive.size()


func add(home_id: int, n_adults: int, n_children: int, n_seniors: int, educations: Array, start_money: float) -> int:
	var i: int
	if _free.is_empty():
		i = alive.size()
		alive.append(0)
		home.append(0)
		adults.append(0)
		children.append(0)
		seniors.append(0)
		money.append(0.0)
		happiness.append(50.0)
		broke.append(0)
		income.append(0.0)
		for k in MAX_ADULTS:
			edu.append(0)
			job.append(NO_JOB)
	else:
		i = _free[_free.size() - 1]
		_free.remove_at(_free.size() - 1)
	alive[i] = 1
	home[i] = home_id
	adults[i] = clampi(n_adults, 0, MAX_ADULTS)
	children[i] = n_children
	seniors[i] = n_seniors
	money[i] = start_money
	happiness[i] = 50.0
	broke[i] = 0
	income[i] = 0.0
	for k in MAX_ADULTS:
		edu[i * MAX_ADULTS + k] = int(educations[k]) if k < educations.size() else 0
		job[i * MAX_ADULTS + k] = NO_JOB
	count += 1
	return i


func remove(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	for k in MAX_ADULTS:
		job[i * MAX_ADULTS + k] = NO_JOB
	_free.append(i)
	count -= 1


## Removes adult slot k (retired, moved out, died), shifting the others left.
## Returns that adult's job code so the caller can free the job.
func remove_adult(i: int, k: int) -> int:
	var base := i * MAX_ADULTS
	var freed := job[base + k]
	for s in range(k, MAX_ADULTS - 1):
		edu[base + s] = edu[base + s + 1]
		job[base + s] = job[base + s + 1]
	edu[base + MAX_ADULTS - 1] = 0
	job[base + MAX_ADULTS - 1] = NO_JOB
	adults[i] = maxi(adults[i] - 1, 0)
	return freed


## Adds an adult (a child grew up); false if the household is full.
func add_adult(i: int, education: int) -> bool:
	if adults[i] >= MAX_ADULTS:
		return false
	var slot := i * MAX_ADULTS + adults[i]
	edu[slot] = education
	job[slot] = NO_JOB
	adults[i] += 1
	return true


func members(i: int) -> int:
	return adults[i] + children[i] + seniors[i]


func employed(i: int) -> int:
	var n := 0
	for k in adults[i]:
		if job[i * MAX_ADULTS + k] != NO_JOB:
			n += 1
	return n


static func job_code(company_id: int, level: int) -> int:
	return company_id * 4 + level


static func job_company(code: int) -> int:
	return code / 4


static func job_level(code: int) -> int:
	return code % 4
