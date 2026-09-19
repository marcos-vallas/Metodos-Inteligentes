extends CharacterBody2D
class_name Agente3

enum TipoNPC {
	WANDERER,  ## Solo deambula (Wander / Idle) sin verse afectado por el jugador
	CHASER,    ## Deambula; al detectar al jugador hace Seek + Arrive; vuelve a deambular si se aleja
	COWARD     ## Deambula; al detectar al jugador hace Flee; vuelve a deambular si se aleja
}

enum Estado {
	CALCULANDO,         
	WANDER,           ## Desplazamiento hacia el objetivo aleatorio
	SEEK,             ## Persecución activa del jugador con evasión por suma de vectores
	FLEE,             ## Huida activa del jugador con evasión por suma de vectores
	SEARCHING_PATH    ## Frenado preventivo ejecutando barrido para encontrar camino seguro
}

@export_category("Configuración General")
@export var tipo_npc: TipoNPC = TipoNPC.CHASER
@export var componente_movimento: MovementComponent
@export var componente_wander: WanderComponent

@export_category("Sensores")
@export var area_grande: Area2D    ## Sensor de Percepción (detecta al Jugador)
@export var area_chica: Area2D     ## Sensor de Proximidad (detecta obstáculos cercanos)
@export var casters: Node2D    ## Sensor direccional para barridos y validación

@export_category("Wander & Idle")
@export var umbral_llegada_punto: float = 20.0     ## Distancia para considerar que llegó al objetivo

@export_category("Seek & Arrive")
@export var arrive_stop_radius: float = 35.0       ## Distancia de parada frente al jugador

@export_category("Evasión por Suma de Vectores")
@export var peso_evasion: float = 1.6              ## Ponderación de la fuerza evasiva sobre la fuerza deseada
@export_flags_2d_physics var mascara_obstaculos: int = 7 ## Capas de paredes y obstáculos (1, 2 y 3)

@export_category("Visual Debug")
@export var debug_draw: bool = true

# Variables de estado y control
var estado_actual: Estado = Estado.WANDER
var objetivo_player: Node2D = null
var objetivo_wander: Vector2 = Vector2.ZERO
var direccion_actual: Vector2 = Vector2.RIGHT


var direccionlibre:Vector2

func _ready() -> void:
		# Conexión del sensor grande (Jugador)
#region Asignacion funciones de deteccion
	if area_grande:
		if not area_grande.body_entered.is_connected(_on_area_grande_body_entered):
			area_grande.body_entered.connect(_on_area_grande_body_entered)
		if not area_grande.body_exited.is_connected(_on_area_grande_body_exited):
			area_grande.body_exited.connect(_on_area_grande_body_exited)
			
	if area_chica:
		if not area_chica.body_entered.is_connected(_on_area_chica_body_entered):
			area_grande.body_entered.connect(_on_area_grande_body_entered)
		if not area_chica.body_exited.is_connected(_on_area_chica_body_exited):
			area_grande.body_exited.connect(_on_area_grande_body_exited)
	pass
#endregion
			
			


#region Deteccion de Bodies

func _on_area_grande_body_entered(body:Node2D):
	pass
func _on_area_grande_body_exited(body:Node2D):
	pass
func _on_area_chica_body_entered(body:Node2D):
	if body.is_in_group("Obstaculos"):
		print("choca obstaculos")
		estado_actual = Estado.CALCULANDO
	pass
func _on_area_chica_body_exited(body:Node2D):
	pass


#endregion
	
	
func buscar_rc_libre() -> RayCast2D:
	var rc_libre : RayCast2D
	var rc_busqueda : RayCast2D
	for i in casters.get_child_count():
		if casters.get_child(i) is RayCast2D:
			rc_busqueda = casters.get_child(i)
			draw1 = rc_busqueda.target_position
			if !rc_busqueda.is_colliding():
				rc_libre = rc_busqueda
	return rc_libre

var draw1:Vector2
func _draw() -> void:
	draw_line(Vector2.ZERO, draw1, Color(1.0, 0.2, 0.8, 0.8), 2.0 )
	
	
	
func _physics_process(delta: float) -> void:
	procesar_comportamiento()
	move_and_slide()
	pass

func procesar_comportamiento():
	match estado_actual:
		Estado.WANDER:
			velocity = componente_wander.wander()
			pass
		Estado.CALCULANDO:
			direccionlibre = buscar_rc_libre().target_position
			print(direccionlibre)
			pasar_camino_libre()
			
func pasar_camino_libre():
	componente_wander.move_direction = direccionlibre
