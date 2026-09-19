extends CharacterBody2D
class_name Agente1


@onready var nav: NavigationAgent2D = $NavigationAgent2D

@export var componente_movimento : MovementComponent


func _physics_process(delta: float) -> void:
	velocity = componente_movimento.wander()
	move_and_slide()


#func seek_player():
	#var mundo : Node2D
	#if self.is_inside_tree():
		#mundo = self.get_tree()
