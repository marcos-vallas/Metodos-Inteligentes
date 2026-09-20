extends Agente3
class_name Coward

@export_category("Components")
@export var state_comp : StateComponent

@export_category("Animation")
@export var animation_tree : AnimationTree
@export var animation_comp : AnimationComponent
@export var sprite_character : Sprite2D

func _ready() -> void:
	animation_comp.setup(animation_tree)

func _process(_delta: float) -> void:
	state_loop()
	animation_loop()
	flip_h_loop()


# --- FUNCIONES DE ESTADO Y ANIMACIÓN ---

func state_loop() -> void:
	state_comp.motion = velocity
	state_comp.check_motion()
	
func animation_loop() -> void:
	animation_comp.play_State(state_comp.state)
	
func flip_h_loop() -> void:
	if state_comp.state == StateComponent.State.STATE_1 or state_comp.state == StateComponent.State.STATE_2:
		if velocity.x < -0.1:
			sprite_character.flip_h = true
		elif velocity.x > 0.1:
			sprite_character.flip_h = false
