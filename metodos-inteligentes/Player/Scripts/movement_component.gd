extends Resource
class_name MovementComponent

@export var speed : int = 400

# Parámetros para Arrive
@export var slowing_radius : float = 120.0
@export var stop_radius : float = 10.0

# Parámetros para Wander (Diagrama del profesor)
@export_category("Custom Wander")
@export var zona_de_movimiento: float = 100.0
var follow_point: Vector2 = Vector2.ZERO

var move_direction = Vector2.ZERO


func _init() -> void:
	resource_local_to_scene = true


# --- CÓDIGO DE MARCOS (Intacto, no afecta al Player) ---
func get_motion() -> Vector2:
	move_direction = Vector2.ZERO
	move_direction.x = int(Input.is_action_pressed("right")) - int(Input.is_action_pressed("left"))
	move_direction.y = int(Input.is_action_pressed("down")) - int(Input.is_action_pressed("up"))
	return move_direction.normalized() * speed


# --- TU CÓDIGO (Steering Behaviors para los NPCs) ---

# 1. SEEK (Perseguir)
func seek(current_pos: Vector2, target_pos: Vector2) -> Vector2:
	move_direction = (target_pos - current_pos).normalized()
	return move_direction * speed

# 2. FLEE (Huir)
func flee(current_pos: Vector2, threat_pos: Vector2) -> Vector2:
	move_direction = (current_pos - threat_pos).normalized()
	return move_direction * speed

# 3. ARRIVE (Llegar y frenar)
func arrive(current_pos: Vector2, target_pos: Vector2) -> Vector2:
	var to_target = target_pos - current_pos
	var distance = to_target.length()
	
	if distance <= stop_radius:
		move_direction = Vector2.ZERO
		return Vector2.ZERO
		
	move_direction = to_target.normalized()
	if distance < slowing_radius:
		var ramped_speed = speed * (distance / slowing_radius)
		return move_direction * ramped_speed
	else:
		return move_direction * speed

# 4. WANDER (Según diagrama con evasión de obstáculos)
func wander(current_pos: Vector2, current_dir: Vector2, raycast: RayCast2D) -> Vector2:
	if current_dir == Vector2.ZERO:
		current_dir = Vector2.RIGHT
		
	# Si no tenemos punto o ya llegamos, generamos uno nuevo
	if follow_point == Vector2.ZERO or current_pos.distance_to(follow_point) < 10.0:
		follow_point = generar_nuevo_follow_point(current_pos, current_dir, raycast)
		
	# Nos dirigimos hacia el follow_point
	return seek(current_pos, follow_point)

func generar_nuevo_follow_point(current_pos: Vector2, current_dir: Vector2, raycast: RayCast2D) -> Vector2:
	var intento = 0
	var nuevo_punto = Vector2.ZERO
	var punto_valido = false
	
	while not punto_valido and intento < 5:
		# Arco frontal de ~108 grados (+- 54 grados)
		var angle_offset = deg_to_rad(randf_range(-54.0, 54.0))
		var direccion_aleatoria = current_dir.rotated(angle_offset)
		
		var distancia = randf_range(zona_de_movimiento * 0.4, zona_de_movimiento)
		nuevo_punto = current_pos + (direccion_aleatoria * distancia)
		
		# Verificación de colisiones con el sensor
		if raycast:
			raycast.target_position = raycast.to_local(nuevo_punto)
			raycast.force_raycast_update()
			if not raycast.is_colliding():
				punto_valido = true
			else:
				intento += 1
		else:
			punto_valido = true
			
	return nuevo_punto
