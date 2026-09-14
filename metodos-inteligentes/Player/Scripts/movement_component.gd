
# movement_component.gd
extends Resource
class_name MovementComponent

@export var speed : int = 400
var move_direction = Vector2.ZERO

func get_motion() -> Vector2:
	move_direction = Vector2.ZERO
	move_direction.x = int(Input.is_action_pressed("right")) - int(Input.is_action_pressed("left"))
	move_direction.y = int(Input.is_action_pressed("down")) - int(Input.is_action_pressed("up"))
	return move_direction.normalized() * speed
