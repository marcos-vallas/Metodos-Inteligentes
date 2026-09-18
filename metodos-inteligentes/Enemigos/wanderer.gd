extends Node
class_name recurso_wanderer

@export var propietario:CharacterBody2D
@export var velocidad = 100
@export var giro_angulo_max = 135
@export var giro_angulo_min = 85

#Para hacerlo con raycast, colocar el raycast2D apuntando hacia el donde mira el enemigo.
@export var rayitos:RayCast2D
func _physics_process(delta: float) -> void:
	if rayitos.is_colliding():
		var giro_actual = randf_range(giro_angulo_min, giro_angulo_max)
		propietario.rotation = giro_actual
	propietario.velocity.x = velocidad
	propietario.move_and_slide()
