extends Resource
class_name WanderComponent


# movement_component.gd
@export var speed : int = 40

# Parámetros para Wander
@export var wander_distance : float = 80.0
@export var wander_radius : float = 40.0
@export var wander_jitter : float = 0.4
var wander_angle : float = 0.0


var move_direction = Vector2.ZERO

# 4. WANDER (Vagar)
func wander() -> Vector2:
	var forward = move_direction if move_direction != Vector2.ZERO else Vector2.RIGHT
	wander_angle += randf_range(-wander_jitter, wander_jitter)
	var circle_center = forward * wander_distance
	var displacement = Vector2(cos(wander_angle), sin(wander_angle)) * wander_radius
	move_direction = (circle_center + displacement).normalized()
	return move_direction * speed
