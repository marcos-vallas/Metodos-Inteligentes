# animation_component.gd
extends Resource
class_name AnimationComponent

var animation_tree : AnimationTree
var animation_playback : AnimationNodeStateMachinePlayback

@export var state_to_animation : Dictionary[StateComponent.State,String] = {
	StateComponent.State.STATE_1: "idle",
	StateComponent.State.STATE_2 : "run"
}

func _init() -> void:
	resource_local_to_scene = true

func setup(tree: AnimationTree) -> void:
	animation_tree = tree
	if animation_tree:
		animation_tree.active = true
		animation_playback = tree["parameters/playback"]
	
func travel_state(state: String) -> void:
	if animation_playback:
		animation_playback.travel(state)

func play_State(state: StateComponent.State) -> void:
	if state in state_to_animation:
		travel_state(state_to_animation[state])
