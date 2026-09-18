extends AnimationPlayer

@export var propietario:CharacterBody2D
@export var movimiento:recurso_wanderer
@export var corre_derecha:Animation



func _ready() -> void:
	movimiento.giro_personaje.connect(cambiar_animacion)

func cambiar_animacion(angulo_de_vision):
	play()
