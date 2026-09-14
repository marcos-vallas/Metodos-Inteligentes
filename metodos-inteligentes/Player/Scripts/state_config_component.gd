# state_config_component.gd
extends Resource
class_name StateConfigComponent

# Lista de estados en orden
@export var states : Array[String] = ["IDLE", "RUN", "ATTACK", "DEAD"]

# Diccionario que mapea estado → animación
@export var state_to_animation : Dictionary[String,String] = {
	"IDLE": "idle",
	"RUN": "run",
	"ATTACK": "att_1",
	"DEAD": "dead"
}
