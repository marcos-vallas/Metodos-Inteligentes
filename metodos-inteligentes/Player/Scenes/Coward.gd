extends CharacterBody2D

@export_category("Components")
@export var movement_comp : MovementComponent
@export var state_comp : StateComponent

@export_category("Animation")
@export var animation_tree : AnimationTree
@export var animation_comp : AnimationComponent

@export_category("IA Target")
@export var player_node: Node2D
@export var distance_to_flee: float = 200.0
@export var distance_to_safe: float = 300.0

# Asegurate de tener un RayCast2D llamado RayCastCentral como hijo del Coward
@onready var raycast = $RayCastCentral 

enum State { WANDER, FLEE }
var current_behavior = State.WANDER

func _ready() -> void:
	animation_comp.setup(animation_tree)

func _physics_process(_delta: float) -> void:
	movement_loop()
	state_loop()
	animation_loop()
	flip_h_loop()

func movement_loop() -> void:
	if player_node:
		var dist = global_position.distance_to(player_node.global_position)
		
		# Transiciones de estado
		if dist < distance_to_flee:
			current_behavior = State.FLEE
		elif dist > distance_to_safe:
			current_behavior = State.WANDER

	# Ejecución del comportamiento
	match current_behavior:
		State.WANDER:
			self.velocity = movement_comp.wander(global_position, movement_comp.move_direction, raycast)
		State.FLEE:
			self.velocity = movement_comp.flee(global_position, player_node.global_position)
			
	self.move_and_slide()

# --- FUNCIONES DE ESTADO Y ANIMACIÓN ---

func state_loop() -> void:
	state_comp.motion = movement_comp.get_motion()
	state_comp.check_motion()
	
func animation_loop() -> void:
	animation_comp.play_State(state_comp.state)
	
func flip_h_loop() -> void:
	if state_comp.state == StateComponent.State.STATE_1 or state_comp.state == StateComponent.State.STATE_2:
		if movement_comp.move_direction.x < -0.1:
			$WarriorBlue.flip_h = true
		elif movement_comp.move_direction.x > 0.1:
			$WarriorBlue.flip_h = false
