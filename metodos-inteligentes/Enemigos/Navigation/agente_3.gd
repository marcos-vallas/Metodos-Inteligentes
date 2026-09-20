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

@export_category("Sensores")
@export var area_grande: Area2D    ## Sensor de Percepción (detecta al Jugador)
@export var area_chica: Area2D     ## Sensor de Proximidad (detecta obstáculos cercanos)
@export var casters: Node2D        ## Contenedor de RayCast2D direccionales
@onready var sprite: Sprite2D

@export_category("Visual Debug")
@export var debug_draw: bool = true

# Variables de estado y control del actor
var estado_actual: Estado = Estado.WANDER
var objetivo_player: Node2D = null
var obstaculos_en_rango: Array[Node2D] = []

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
	# Asegurar que el detector de obstáculos exista por defecto si no se asignó en Inspector
	if not componente_detector:
		componente_detector = ObstacleDetectorComponent.new()
	
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
	# 1. Alinear el contenedor de sensores con la dirección deseada del agente hacia el objetivo
	var dir_deseada: Vector2 = obtener_direccion_deseada()
	if casters and dir_deseada != Vector2.ZERO:
		casters.rotation = dir_deseada.angle()
	
	# 2. Actualizar raycasts sensoriales
	if componente_detector:
		componente_detector.actualizar_raycasts(casters)
	
	# 3. Procesar comportamiento y decisiones de movimiento
	procesar_comportamiento(delta)
	
	# 4. Movimiento físico
	move_and_slide()
	
	if debug_draw:
		queue_redraw()

#region Transiciones de Estado de Evasión (FSM)
func iniciar_esquiva() -> void:
	estado_actual = Estado.ESQUIVANDO
	if componente_detector:
		componente_detector.actualizar_raycasts(casters)
	if componente_esquiva:
		componente_esquiva.iniciar_maniobra()

func retornar_a_estado_normal() -> void:
	var dir_salida: Vector2 = componente_esquiva.direccion_actual if componente_esquiva else velocity.normalized()
	if tipo_npc == TipoNPC.WANDERER or objetivo_player == null or not is_instance_valid(objetivo_player):
		estado_actual = Estado.WANDER
		if componente_wander:
			componente_wander.establecer_objetivo(dir_salida)
	else:
		if tipo_npc == TipoNPC.SEEKER:
			estado_actual = Estado.SEEK
		elif tipo_npc == TipoNPC.FLEEKER:
			estado_actual = Estado.FLEE

func obtener_direccion_amenaza() -> Vector2:
	if tipo_npc == TipoNPC.FLEEKER and objetivo_player and is_instance_valid(objetivo_player):
		return (objetivo_player.global_position - global_position).normalized()
	return Vector2.ZERO

func obtener_direccion_deseada() -> Vector2:
	match tipo_npc:
		TipoNPC.SEEKER:
			if objetivo_player and is_instance_valid(objetivo_player):
				var offset: Vector2 = objetivo_player.global_position - global_position
				if offset.length_squared() > 1.0:
					return offset.normalized()
		TipoNPC.FLEEKER:
			if objetivo_player and is_instance_valid(objetivo_player):
				var offset: Vector2 = global_position - objetivo_player.global_position
				if offset.length_squared() > 1.0:
					return offset.normalized()
		TipoNPC.WANDERER:
			if componente_wander and componente_wander.direccion_objetivo != Vector2.ZERO:
				return componente_wander.direccion_objetivo.normalized()
	
	if velocity.length_squared() > 1.0:
		return velocity.normalized()
	return Vector2.RIGHT
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
				ya_llego_al_player = global_position.distance_to(objetivo_player.global_position) <= 35.0
		
		if not ya_llego_al_player and componente_detector and componente_detector.hay_obstaculo_anticipado(global_position, casters):
			iniciar_esquiva()

	match estado_actual:
		Estado.WANDER:
			if componente_wander:
				velocity = componente_wander.wander(delta)

		Estado.ESQUIVANDO:
			if not componente_esquiva:
				return
				
			var dir_amenaza: Vector2 = obtener_direccion_amenaza()
			var dir_deseada: Vector2 = obtener_direccion_deseada()
			var fallback_wander: Vector2 = componente_wander.direccion_objetivo if componente_wander else Vector2.ZERO
			
			# Delegación completa de la maniobra al EsquivaComponent con direccion_deseada
			velocity = componente_esquiva.procesar_maniobra(
				self, delta, componente_detector, casters, area_chica, obstaculos_en_rango, dir_amenaza, fallback_wander, dir_deseada
			)
			
			# Sincronización de rumbo en Wander si se bordea o despega de una pared
			if componente_detector and componente_detector.hay_pared_en_area(area_chica, obstaculos_en_rango):
				if componente_wander:
					componente_wander.establecer_objetivo(componente_esquiva.direccion_actual, true)
			
			# Evaluación de salida segura de la esquiva
			var espacio = get_world_2d().direct_space_state
			if componente_esquiva.puede_salir(componente_detector, global_position, casters, obstaculos_en_rango, dir_amenaza, espacio, get_rid()):
				retornar_a_estado_normal()

		Estado.SEEK:
			if objetivo_player == null or not is_instance_valid(objetivo_player):
				estado_actual = Estado.WANDER
				return
			if componente_seek:
				velocity = componente_seek.calcular_velocidad(global_position, objetivo_player.global_position, delta)
			else:
				var a_player: Vector2 = objetivo_player.global_position - global_position
				var stop_dist: float = componente_seek.arrive_stop_radius if componente_seek else 35.0
				if a_player.length() <= stop_dist:
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
				var dir_salida: Vector2 = velocity.normalized() if velocity != Vector2.ZERO else Vector2.RIGHT
				componente_wander.establecer_objetivo(dir_salida)

func _on_area_chica_body_entered(body: Node2D) -> void:
	if componente_detector and componente_detector.es_obstaculo(body):
		if not obstaculos_en_rango.has(body):
			obstaculos_en_rango.append(body)
		iniciar_esquiva()

func _on_area_chica_body_exited(body: Node2D) -> void:
	if componente_detector and componente_detector.es_obstaculo(body):
		obstaculos_en_rango.erase(body)
		obstaculos_en_rango = obstaculos_en_rango.filter(func(b): return is_instance_valid(b))
		if componente_detector:
			componente_detector.actualizar_raycasts(casters)
		if estado_actual == Estado.ESQUIVANDO and componente_esquiva:
			var dir_amenaza: Vector2 = obtener_direccion_amenaza()
			var espacio = get_world_2d().direct_space_state
			if componente_esquiva.puede_salir(componente_detector, global_position, casters, obstaculos_en_rango, dir_amenaza, espacio, get_rid()):
				retornar_a_estado_normal()
#endregion

#region Visual Debug
func _draw() -> void:
	if debug_draw and componente_detector:
		var dir_local: Vector2 = componente_detector.ultimo_rc_objetivo
		if casters:
			dir_local = dir_local.rotated(casters.rotation)
		draw_line(Vector2.ZERO, dir_local, Color(1.0, 0.2, 0.8, 0.8), 2.0)
#endregion
