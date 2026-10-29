class_name MapGrid
extends RefCounted
## Shared math for the 8 m zoning grid and the playable map square.


static func world_to_cell(world_pos: Vector3, cell_size: float) -> Vector2i:
	return Vector2i(floori(world_pos.x / cell_size), floori(world_pos.z / cell_size))


static func cell_center(cell: Vector2i, cell_size: float) -> Vector3:
	return Vector3((cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size)


static func is_inside(world_pos: Vector3, playable_half: float) -> bool:
	return absf(world_pos.x) <= playable_half and absf(world_pos.z) <= playable_half
