# animation_component.gd
extends Resource
class_name AnimationComponent

var animation_tree : AnimationTree
var animation_playback : AnimationNodeStateMachinePlayback

@export var state_to_animation : Dictionary[StateComponent.State,String] = {
	StateComponent.State.STATE_1: "idle",
	StateComponent.State.STATE_2 : "run"
}

func setup(tree: AnimationTree) -> void:
	animation_tree = tree
	animation_playback = tree["parameters/playback"]
	
func travel_state(state: String) -> void:
	if animation_playback:
		animation_playback.travel(state)

func play_State(state:StateComponent.State) -> void:
	match state:
		StateComponent.State.STATE_1:
			travel_state(state_to_animation[state])
		StateComponent.State.STATE_2:
			travel_state(state_to_animation[state])
		StateComponent.State.STATE_3:
			travel_state(state_to_animation[state])
