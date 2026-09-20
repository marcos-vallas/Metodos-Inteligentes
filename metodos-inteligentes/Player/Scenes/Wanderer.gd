extends Agente3
class_name Wanderer


@export_category("Components")
@export var state_comp : StateComponent

@export_category("Animation")
@export var animation_tree : AnimationTree
@export var animation_comp : AnimationComponent
@export var sprite_character : Sprite2D

func _ready() -> void:
	super._ready()
	
	# Fallback para vincular el Sprite si no se asignó en el Inspector
	if not sprite_character:
		sprite_character = get_node_or_null("WarriorBlue") as Sprite2D
		if not sprite_character:
			sprite_character = get_node_or_null("Sprite2D") as Sprite2D
			
	if animation_tree:
		animation_tree.active = true
		
	if animation_comp and animation_tree:
		animation_comp.setup(animation_tree)

func _physics_process(delta: float) -> void:
	# 1. Agente3 procesa sensores, raycasts, comportamientos (Wander/Esquiva) y move_and_slide()
	super._physics_process(delta)
	
	# 2. En base a la velocidad resultante de la física, actualizar estado y animación
	state_loop()
	animation_loop()
	flip_h_loop()

func state_loop() -> void:
	if not state_comp:
		return
	
	# Si la velocidad es insignificante, motion es ZERO para activar Idle (STATE_1)
	if velocity.length_squared() < 1.0:
		state_comp.motion = Vector2.ZERO
	else:
		state_comp.motion = velocity
		
	state_comp.check_motion()

func animation_loop() -> void:
	if animation_comp and state_comp:
		animation_comp.play_State(state_comp.state)

func flip_h_loop() -> void:
	if not sprite_character:
		return
	
	# Se orienta el sprite horizontalmente cuando hay movimiento claro en X
	if abs(velocity.x) > 0.5:
		sprite_character.flip_h = (velocity.x < 0.0)
