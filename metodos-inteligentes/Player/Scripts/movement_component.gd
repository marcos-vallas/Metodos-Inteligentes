extends Resource
class_name MovementComponent

# movement_component.gd
@export var speed : int = 400

# Parámetros para Arrive
@export var slowing_radius : float = 120.0
@export var stop_radius : float = 10.0

# Parámetros para Wander
@export var wander_distance : float = 80.0
@export var wander_radius : float = 40.0
@export var wander_jitter : float = 0.4
var wander_angle : float = 0.0

var move_direction = Vector2.ZERO

func get_motion() -> Vector2:
	move_direction = Vector2.ZERO
	move_direction.x = int(Input.is_action_pressed("right")) - int(Input.is_action_pressed("left"))
	move_direction.y = int(Input.is_action_pressed("down")) - int(Input.is_action_pressed("up"))
	return move_direction.normalized() * speed
	
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

# 4. WANDER (Vagar)
func wander() -> Vector2:
	var forward = move_direction if move_direction != Vector2.ZERO else Vector2.RIGHT
	wander_angle += randf_range(-wander_jitter, wander_jitter)
	var circle_center = forward * wander_distance
	var displacement = Vector2(cos(wander_angle), sin(wander_angle)) * wander_radius
	move_direction = (circle_center + displacement).normalized()
	return move_direction * speed
	
	
