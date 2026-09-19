extends Area2D
class_name coward_movimiento

@export var propietario:CharacterBody2D
@export var velocidad = 100

var wanderer_propio: recurso_wanderer

func _ready() -> void:
	for hijo in propietario.get_children():
		if hijo is recurso_wanderer:
			wanderer_propio = hijo
			break


func _on_body_entered(body: Node2D) -> void:
	if body is Jugador:
		wanderer_propio.set_physics_process(false)
		var direccion = propietario.global_position - body.global_position
		direccion = direccion.normalized()

		propietario.velocity = direccion * velocidad
		propietario.move_and_slide()




func _on_body_exited(body: Node2D) -> void:
	if body is Jugador:
		wanderer_propio.set_physics_process(true)
