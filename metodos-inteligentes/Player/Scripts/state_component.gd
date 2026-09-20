extends Resource
class_name StateComponent

# state
enum State {
	STATE_1, #Idle
	STATE_2, #Run
	STATE_3, #Attack1
	STATE_4
}


var state : State = State.STATE_1
var motion : Vector2 = Vector2.ZERO

func _init() -> void:
	resource_local_to_scene = true

func check_motion():
	if motion != Vector2.ZERO and state == State.STATE_1:
		state = State.STATE_2
		update_animation()
	if motion == Vector2.ZERO and state == State.STATE_2:
		state = State.STATE_1
		update_animation()
		
func update_animation():
	#print("update_animation")
	pass
