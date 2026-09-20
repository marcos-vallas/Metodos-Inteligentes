extends CharacterBody2D
class_name Agente3

enum TipoNPC {
	WANDERER,  ## Solo deambula (Wander), ignora al jugador
	SEEKER,    ## Deambula; persigue al jugador al detectarlo; esquiva obstáculos; vuelve a Wander si se aleja
	FLEEKER    ## Deambula; huye del jugador al detectarlo; esquiva obstáculos; vuelve a Wander si se aleja
}

# Alias para compatibilidad con nombres previos
const CHASER = TipoNPC.SEEKER
const COWARD = TipoNPC.FLEEKER

enum Estado {
	ESQUIVANDO,
	CALCULANDO,
	WANDER,           ## Desplazamiento hacia el objetivo aleatorio
	SEEK,             ## Persecución activa del jugador
	FLEE,             ## Huida activa del jugador
	SEARCHING_PATH    ## Frenado preventivo ejecutando barrido para encontrar camino seguro
}

@export_category("Configuración General")
@export var tipo_npc: TipoNPC = TipoNPC.WANDERER: set = set_tipo_npc

@export_category("Componentes")
@export var componente_wander: WanderComponent
@export var componente_esquiva: EsquivaComponent
@export var componente_seek: SeekComponent
@export var componente_flee: FleeComponent
@export var componente_detector: ObstacleDetectorComponent

@export_category("Evasión de Obstáculos")
## Tiempo mínimo que permanece en estado de esquiva para evitar cancelaciones prematuras u oscilaciones
@export var tiempo_min_esquivando: float = 0.35
## Tiempo máximo continuo en estado de esquiva antes de forzar un desvío angular para despegarse de paredes
@export var tiempo_max_esquivando: float = 1.2
## Distancia máxima en píxeles a la que un raycast frontal activa anticipadamente la evasión
@export var distancia_anticipacion_obstaculo: float = 80.0

@export_category("Sensores")
@export var area_grande: Area2D    ## Sensor de Percepción (detecta al Jugador)
@export var area_chica: Area2D     ## Sensor de Proximidad (detecta obstáculos cercanos)
@export var casters: Node2D        ## Contenedor de RayCast2D direccionales
@onready var sprite: Sprite2D = $Sprite2D

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
var timer_esquivando: float = 0.0

## Permite cambiar el rol del NPC en caliente desde el Inspector
func set_tipo_npc(nuevo_tipo: TipoNPC) -> void:
	tipo_npc = nuevo_tipo
	if not is_inside_tree():
		return
	if tipo_npc == TipoNPC.WANDERER:
		objetivo_player = null
		if estado_actual != Estado.ESQUIVANDO:
			estado_actual = Estado.WANDER
	else:
		if area_grande:
			for b in area_grande.get_overlapping_bodies():
				if b != self and (b.is_in_group("player") or b.is_in_group("Player")):
					objetivo_player = b
					if estado_actual != Estado.ESQUIVANDO:
						estado_actual = Estado.SEEK if tipo_npc == TipoNPC.SEEKER else Estado.FLEE
					return

func _ready() -> void:
	# Asegurar que el detector de obstáculos exista por defecto
	if not componente_detector:
		componente_detector = ObstacleDetectorComponent.new()
	if mascara_obstaculos != 0 and componente_detector:
		componente_detector.mascara_obstaculos = mascara_obstaculos
	if distancia_anticipacion_obstaculo > 0.0 and componente_detector:
		componente_detector.distancia_anticipacion = distancia_anticipacion_obstaculo
	
	# Conexión de sensores de percepción y proximidad
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
	
	set_tipo_npc(tipo_npc)

func _physics_process(delta: float) -> void:
	# 1. Alinear el contenedor de sensores con la velocidad
	if casters and velocity.length_squared() > 1.0:
		casters.rotation = velocity.angle()
	
	# 2. Forzar actualización de raycasts sensoriales
	actualizar_raycasts()
	
	# 3. Procesar comportamiento y decisiones de evasión
	procesar_comportamiento(delta)
	
	# 4. Movimiento físico
	move_and_slide()

func _process(_delta: float) -> void:
	actualizar_orientacion_sprite()

func actualizar_orientacion_sprite() -> void:
	if sprite:
		if velocity.x < -1.0:
			sprite.flip_h = true
		elif velocity.x > 1.0:
			sprite.flip_h = false

#region Delegación sensorial al ObstacleDetectorComponent
func es_obstaculo(collider: Object) -> bool:
	return componente_detector.es_obstaculo(collider) if componente_detector else false

func es_pared(collider: Object) -> bool:
	return componente_detector.es_pared(collider) if componente_detector else false

func rc_toca_obstaculo(rc: RayCast2D) -> bool:
	return componente_detector.rc_toca_obstaculo(rc) if componente_detector else false

func rc_toca_pared(rc: RayCast2D) -> bool:
	return componente_detector.rc_toca_pared(rc) if componente_detector else false

func hay_pared_en_area_chica() -> bool:
	return componente_detector.hay_pared_en_area(area_chica, obstaculos_en_rango) if componente_detector else false

func obtener_vector_contrario_a_pared() -> Vector2:
	return componente_detector.obtener_vector_contrario_a_pared(casters) if componente_detector else Vector2.ZERO

func hay_obstaculo_anticipado() -> bool:
	if not componente_detector:
		return false
	return componente_detector.hay_obstaculo_anticipado(global_position, casters, distancia_anticipacion_obstaculo)

func actualizar_raycasts() -> void:
	if componente_detector:
		componente_detector.actualizar_raycasts(casters)

func esta_direccion_obstruida(dir_global: Vector2, distancia: float = 60.0) -> bool:
	if not componente_detector:
		return false
	var espacio = get_world_2d().direct_space_state
	return componente_detector.esta_direccion_obstruida(espacio, global_position, dir_global, distancia, get_rid())
#endregion

#region Control de Evasión
func iniciar_esquiva() -> void:
	estado_actual = Estado.ESQUIVANDO
	timer_esquivando = 0.0
	actualizar_raycasts()
	actualizar_direccion_evasion()

func puede_salir_de_esquiva() -> bool:
	if timer_esquivando < tiempo_min_esquivando:
		return false
	if not obstaculos_en_rango.is_empty():
		return false
	if hay_obstaculo_anticipado():
		return false
	if tipo_npc == TipoNPC.FLEEKER and objetivo_player != null and is_instance_valid(objetivo_player):
		var dir_flee: Vector2 = (global_position - objetivo_player.global_position).normalized()
		if esta_direccion_obstruida(dir_flee, distancia_anticipacion_obstaculo * 0.75):
			return false
	return true

func retornar_a_estado_normal() -> void:
	timer_esquivando = 0.0
	if tipo_npc == TipoNPC.WANDERER or objetivo_player == null or not is_instance_valid(objetivo_player):
		estado_actual = Estado.WANDER
		if componente_wander:
			componente_wander.establecer_objetivo(direccionlibre)
	else:
		if tipo_npc == TipoNPC.SEEKER:
			estado_actual = Estado.SEEK
		elif tipo_npc == TipoNPC.FLEEKER:
			estado_actual = Estado.FLEE

func actualizar_direccion_evasion() -> void:
	if not componente_detector:
		return
		
	var dir_amenaza: Vector2 = Vector2.ZERO
	if tipo_npc == TipoNPC.FLEEKER and objetivo_player and is_instance_valid(objetivo_player):
		dir_amenaza = (objetivo_player.global_position - global_position).normalized()
		
	var fallback_wander: Vector2 = componente_wander.direccion_objetivo if componente_wander else Vector2.ZERO
	var es_pared: bool = hay_pared_en_area_chica()
	
	direccionlibre = componente_detector.calcular_direccion_evasion(
		self, casters, area_chica, obstaculos_en_rango, dir_amenaza, fallback_wander
	)
	
	if componente_esquiva:
		componente_esquiva.establecer_direccion(direccionlibre)
	if es_pared and componente_wander:
		componente_wander.establecer_objetivo(direccionlibre, true)

func forzar_despegue_pared() -> void:
	if not componente_detector:
		return
		
	var dir_amenaza: Vector2 = Vector2.ZERO
	if tipo_npc == TipoNPC.FLEEKER and objetivo_player and is_instance_valid(objetivo_player):
		dir_amenaza = (objetivo_player.global_position - global_position).normalized()
		
	direccionlibre = componente_detector.forzar_despegue_pared(
		self, casters, area_chica, obstaculos_en_rango, dir_amenaza
	)
	
	if componente_esquiva:
		componente_esquiva.establecer_direccion(direccionlibre)
		velocity = direccionlibre * componente_esquiva.speed
	else:
		velocity = direccionlibre * 70.0
		
	if casters:
		casters.rotation = direccionlibre.angle()
	if componente_wander:
		componente_wander.establecer_objetivo(direccionlibre, true)
#endregion

#region Máquina de Estados y Comportamiento
func procesar_comportamiento(delta: float = 0.0) -> void:
	# Detección anticipada de obstáculos cuando no se está esquivando activamente
	if estado_actual != Estado.ESQUIVANDO:
		var ya_llego_al_player: bool = false
		if tipo_npc == TipoNPC.SEEKER and objetivo_player != null and is_instance_valid(objetivo_player):
			if componente_seek:
				ya_llego_al_player = componente_seek.ha_llegado(global_position, objetivo_player.global_position)
			else:
				ya_llego_al_player = global_position.distance_to(objetivo_player.global_position) <= arrive_stop_radius
		
		if not ya_llego_al_player and hay_obstaculo_anticipado():
			iniciar_esquiva()

	match estado_actual:
		Estado.WANDER:
			if componente_wander:
				velocity = componente_wander.wander(delta)
		Estado.ESQUIVANDO:
			timer_esquivando += delta
			if timer_esquivando >= tiempo_max_esquivando:
				forzar_despegue_pared()
				timer_esquivando = 0.0
			else:
				actualizar_direccion_evasion()
				if puede_salir_de_esquiva():
					retornar_a_estado_normal()
			
			if componente_esquiva:
				velocity = componente_esquiva.esquivar(direccionlibre, delta)
			else:
				velocity = direccionlibre * 70.0

		Estado.SEEK:
			if objetivo_player == null or not is_instance_valid(objetivo_player):
				estado_actual = Estado.WANDER
				return
			if componente_seek:
				velocity = componente_seek.calcular_velocidad(global_position, objetivo_player.global_position, delta)
			else:
				var a_player: Vector2 = objetivo_player.global_position - global_position
				if a_player.length() <= arrive_stop_radius:
					velocity = Vector2.ZERO
				else:
					var dir_seek: Vector2 = a_player.normalized()
					if componente_esquiva:
						velocity = componente_esquiva.esquivar(dir_seek, delta)
					else:
						velocity = dir_seek * 70.0

		Estado.FLEE:
			if objetivo_player == null or not is_instance_valid(objetivo_player):
				estado_actual = Estado.WANDER
				return
			if componente_flee:
				velocity = componente_flee.calcular_velocidad(global_position, objetivo_player.global_position, delta)
			else:
				var dir_flee: Vector2 = (global_position - objetivo_player.global_position).normalized()
				if componente_esquiva:
					velocity = componente_esquiva.esquivar(dir_flee, delta)
				else:
					velocity = dir_flee * 70.0
#endregion

#region Señales de Sensores (Percepción y Proximidad)
func _on_area_grande_body_entered(body: Node2D) -> void:
	if tipo_npc == TipoNPC.WANDERER:
		return
	if body.is_in_group("player") or body.is_in_group("Player"):
		objetivo_player = body
		if estado_actual != Estado.ESQUIVANDO:
			if tipo_npc == TipoNPC.SEEKER:
				estado_actual = Estado.SEEK
			elif tipo_npc == TipoNPC.FLEEKER:
				estado_actual = Estado.FLEE

func _on_area_grande_body_exited(body: Node2D) -> void:
	if tipo_npc == TipoNPC.WANDERER:
		return
	if body == objetivo_player:
		objetivo_player = null
		if estado_actual != Estado.ESQUIVANDO:
			estado_actual = Estado.WANDER
			if componente_wander:
				var dir_salida: Vector2 = velocity.normalized() if velocity != Vector2.ZERO else direccion_actual
				componente_wander.establecer_objetivo(dir_salida)

func _on_area_chica_body_entered(body: Node2D) -> void:
	if es_obstaculo(body):
		if not obstaculos_en_rango.has(body):
			obstaculos_en_rango.append(body)
		iniciar_esquiva()

func _on_area_chica_body_exited(body: Node2D) -> void:
	if es_obstaculo(body):
		obstaculos_en_rango.erase(body)
		obstaculos_en_rango = obstaculos_en_rango.filter(func(b): return is_instance_valid(b))
		actualizar_raycasts()
		if puede_salir_de_esquiva():
			retornar_a_estado_normal()
#endregion

#region Visual Debug
func _draw() -> void:
	if debug_draw and componente_detector:
		draw_line(Vector2.ZERO, componente_detector.ultimo_rc_objetivo, Color(1.0, 0.2, 0.8, 0.8), 2.0)
#endregion
