extends CharacterBody2D
class_name Agente3

enum TipoNPC {
	WANDERER,  ## Solo deambula (Wander / Idle) sin verse afectado por el jugador
	CHASER,    ## Deambula; al detectar al jugador hace Seek + Arrive; vuelve a deambular si se aleja
	COWARD     ## Deambula; al detectar al jugador hace Flee; vuelve a deambular si se aleja
}

enum Estado {
	ESQUIVANDO,
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
@export var componente_esquiva: EsquivaComponent

@export_category("Sensores")
@export var area_grande: Area2D    ## Sensor de Percepción (detecta al Jugador)
@export var area_chica: Area2D     ## Sensor de Proximidad (detecta obstáculos cercanos)
@export var casters: Node2D    ## Sensor direccional para barridos y validación
@onready var sprite : Sprite2D = $Sprite2D

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

var direccionlibre: Vector2 = Vector2.ZERO
var obstaculos_en_rango: Array[Node2D] = []


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
			area_chica.body_entered.connect(_on_area_chica_body_entered)
		if not area_chica.body_exited.is_connected(_on_area_chica_body_exited):
			area_chica.body_exited.connect(_on_area_chica_body_exited)
	pass
#endregion
			
			
func actualizar_orientacion_sprite() -> void:
	if sprite:
		if velocity.x < -1.0:
			sprite.flip_h = true
		elif velocity.x > 1.0:
			sprite.flip_h = false

#region Deteccion de Bodies

func _on_area_grande_body_entered(body:Node2D):
	pass
func _on_area_grande_body_exited(body:Node2D):
	pass
func _on_area_chica_body_entered(body: Node2D) -> void:
	if body.is_in_group("Obstaculos"):
		if not obstaculos_en_rango.has(body):
			obstaculos_en_rango.append(body)
		estado_actual = Estado.ESQUIVANDO
		actualizar_direccion_evasion()

func _on_area_chica_body_exited(body: Node2D) -> void:
	if body.is_in_group("Obstaculos"):
		obstaculos_en_rango.erase(body)
		obstaculos_en_rango = obstaculos_en_rango.filter(func(b): return is_instance_valid(b))
		if obstaculos_en_rango.is_empty():
			estado_actual = Estado.WANDER
			if componente_wander:
				componente_wander.establecer_objetivo(direccionlibre)

#endregion
	
func buscar_rc_libre() -> RayCast2D:
	var rc_libre : RayCast2D
	var rc_busqueda : RayCast2D
	for i in casters.get_child_count():
		if casters.get_child(i) is RayCast2D:
			rc_busqueda = casters.get_child(i)
			draw1 = rc_busqueda.target_position
			if !rc_busqueda.is_colliding():
				return rc_busqueda
	return rc_libre

var draw1: Vector2
func _draw() -> void:
	draw_line(Vector2.ZERO, draw1, Color(1.0, 0.2, 0.8, 0.8), 2.0)
	
func _physics_process(delta: float) -> void:
	procesar_comportamiento(delta)
	move_and_slide()
	if casters and velocity.length_squared() > 1.0:
		casters.rotation = velocity.angle()
	
func _process(delta: float) -> void:
	actualizar_orientacion_sprite()

func actualizar_direccion_evasion() -> void:
	var rc: RayCast2D = buscar_rc_libre()
	if rc:
		direccionlibre = (rc.to_global(rc.target_position) - rc.global_position).normalized()
	else:
		if velocity != Vector2.ZERO:
			direccionlibre = -velocity.normalized()
		elif componente_wander:
			direccionlibre = -componente_wander.direccion_objetivo
		else:
			direccionlibre = Vector2.LEFT

func procesar_comportamiento(delta: float = 0.0) -> void:
	match estado_actual:
		Estado.WANDER:
			if componente_wander:
				velocity = componente_wander.wander(delta)
		Estado.ESQUIVANDO:
			actualizar_direccion_evasion()
			if componente_esquiva:
				velocity = componente_esquiva.esquivar(direccionlibre, delta)
			else:
				velocity = direccionlibre * 70.0
