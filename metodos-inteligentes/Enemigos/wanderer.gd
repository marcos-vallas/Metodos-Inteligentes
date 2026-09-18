extends Node
class_name recurso_wanderer

@export var propietario:CharacterBody2D
@export var velocidad = 100
@export var giro_angulo_max = 135
@export var giro_angulo_min = 85
signal giro_personaje(angulo:float)

#Para hacerlo con raycast, colocar el raycast2D apuntando hacia el donde mira el enemigo.
@export var rayitos:RayCast2D
func _physics_process(delta: float) -> void:
	if rayitos.is_colliding():
		var giro_actual = randf_range(giro_angulo_min, giro_angulo_max)
		propietario.rotation_degrees += giro_actual
		var angulo_de_vision = propietario.global_rotation_degrees
		giro_personaje.emit(angulo_de_vision)
		print(angulo_de_vision)
	propietario.velocity = propietario.transform.x * velocidad
	propietario.move_and_slide()
