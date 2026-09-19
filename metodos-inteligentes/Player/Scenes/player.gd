extends CharacterBody2D
class_name Jugador

@export_category("Components")
@export var movement_comp : MovementComponent
@export var state_comp : StateComponent
@export_category("Animation")
@export var animation_tree : AnimationTree #= $AnimationTree
@export var animation_comp : AnimationComponent





func _ready() -> void:
	animation_comp.setup(animation_tree) 
	
	
	
func _physics_process(delta: float) -> void:
	movement_loop()
	state_loop()
	animation_loop()
	flip_h_loop()
	
# Component calling
func movement_loop() -> void:
	self.velocity = movement_comp.get_motion()
	self.move_and_slide()
	
func state_loop() -> void:
	state_comp.motion = movement_comp.get_motion()
	state_comp.check_motion()
	
func animation_loop() -> void:
	animation_comp.play_State(state_comp.state)
	
func flip_h_loop() -> void:
	if state_comp.state == StateComponent.State.STATE_1 or StateComponent.State.STATE_2:
		if movement_comp.move_direction.x < -00.1:
			$WarriorBlue.flip_h = true
		if movement_comp.move_direction.x > 00.1:
			$WarriorBlue.flip_h = false
