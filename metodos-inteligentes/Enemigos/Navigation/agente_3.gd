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

@export var componente_movimento: MovementComponent
@export var componente_wander: WanderComponent
@export var componente_esquiva: EsquivaComponent

@export_category("Evasión de Obstáculos")
## Tiempo máximo continuo en estado de esquiva antes de forzar un desvío angular para despegarse de paredes
@export var tiempo_max_esquivando: float = 1.2

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
var timer_esquivando: float = 0.0

## Permite cambiar la clase del NPC en caliente desde el Inspector
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

## Verifica si un collider pertenece al grupo de obstáculos o paredes
func es_obstaculo(collider: Object) -> bool:
	if collider == null:# or collider == self:
		return false
	if collider is Node:
		return collider.is_in_group("Obstaculos") or collider.is_in_group("obstaculos") or collider.is_in_group("Pared") or collider.is_in_group("pared") or collider.is_in_group("Paredes")
	return false

## Verifica si un collider pertenece específicamente al grupo de Paredes
func es_pared(collider: Object) -> bool:
	if collider == null or collider == self:
		return false
	if collider is Node:
		return collider.is_in_group("Pared") or collider.is_in_group("pared") or collider.is_in_group("Paredes")
	return false

## Verifica si un RayCast2D está colisionando específicamente contra un obstáculo
func rc_toca_obstaculo(rc: RayCast2D) -> bool:
	if not rc.is_colliding():
		return false
	return es_obstaculo(rc.get_collider())

## Verifica si un RayCast2D está colisionando específicamente contra una pared
func rc_toca_pared(rc: RayCast2D) -> bool:
	if not rc.is_colliding():
		return false
	return es_pared(rc.get_collider())

## Verifica si actualmente hay algún objeto del grupo Pared dentro del AreaChica
func hay_pared_en_area_chica() -> bool:
	for b in obstaculos_en_rango:
		if is_instance_valid(b) and es_pared(b):
			return true
	if area_chica:
		for b in area_chica.get_overlapping_bodies():
			if is_instance_valid(b) and es_pared(b):
				return true
	return false

## Calcula un vector contrario a la dirección de los raycasts que detectan la pared
func obtener_vector_contrario_a_pared() -> Vector2:
	var suma_dirs: Vector2 = Vector2.ZERO
	if casters:
		for i in casters.get_child_count():
			var hijo = casters.get_child(i)
			if hijo is RayCast2D and rc_toca_pared(hijo):
				var dir_rayo: Vector2 = (hijo.to_global(hijo.target_position) - hijo.global_position).normalized()
				if dir_rayo != Vector2.ZERO:
					suma_dirs += dir_rayo
	
	if suma_dirs != Vector2.ZERO:
		return -suma_dirs.normalized()
	return Vector2.ZERO

#region Deteccion de Bodies

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
		estado_actual = Estado.ESQUIVANDO
		timer_esquivando = 0.0
		actualizar_direccion_evasion()

func _on_area_chica_body_exited(body: Node2D) -> void:
	if es_obstaculo(body):
		obstaculos_en_rango.erase(body)
		obstaculos_en_rango = obstaculos_en_rango.filter(func(b): return is_instance_valid(b))
		if obstaculos_en_rango.is_empty():
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

#endregion
	
func buscar_rc_libre() -> RayCast2D:
	var rc_libre : RayCast2D = null
	for i in casters.get_child_count():
		var hijo = casters.get_child(i)
		if hijo is RayCast2D:
			draw1 = hijo.target_position
			if not rc_toca_obstaculo(hijo):
				return hijo
	return rc_libre

## Fuerza el despegue calculando un vector contrario a la pared SOLO si hay una pared en AreaChica
func forzar_despegue_pared() -> void:
	if hay_pared_en_area_chica():
		var vec_contrario: Vector2 = obtener_vector_contrario_a_pared()
		if vec_contrario != Vector2.ZERO:
			direccionlibre = vec_contrario
			if componente_esquiva:
				componente_esquiva.establecer_direccion(direccionlibre)
				velocity = direccionlibre * componente_esquiva.speed
			else:
				velocity = direccionlibre * 70.0
			if casters:
				casters.rotation = direccionlibre.angle()
			if componente_wander:
				componente_wander.establecer_objetivo(direccionlibre, true)
			return

	var rc_fallback: RayCast2D = buscar_rc_libre()
	if rc_fallback:
		direccionlibre = (rc_fallback.to_global(rc_fallback.target_position) - rc_fallback.global_position).normalized()
	else:
		direccionlibre = -velocity.normalized() if velocity != Vector2.ZERO else Vector2.LEFT
	if componente_esquiva:
		componente_esquiva.establecer_direccion(direccionlibre)
	
	if componente_wander:
		componente_wander.establecer_objetivo(direccionlibre, true)

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
	# 1. El empuje en contra de la pared se realiza SOLO si al AreaChica entró un body del grupo "Pared"
	if hay_pared_en_area_chica():
		var vec_pared: Vector2 = obtener_vector_contrario_a_pared()
		if vec_pared != Vector2.ZERO:
			direccionlibre = vec_pared
			if componente_esquiva:
				componente_esquiva.establecer_direccion(direccionlibre)
			if componente_wander:
				componente_wander.establecer_objetivo(direccionlibre, true)
			return
	
	# 2. Para otros obstáculos (árboles, rocas), buscamos el primer raycast libre según prioridad
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
	
	if componente_esquiva:
		componente_esquiva.establecer_direccion(direccionlibre)

func procesar_comportamiento(delta: float = 0.0) -> void:
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
				var rc_frontal: RayCast2D = casters.get_child(0) as RayCast2D if casters and casters.get_child_count() > 0 else null
				if rc_frontal and rc_toca_obstaculo(rc_frontal):
					actualizar_direccion_evasion()
			
			if componente_esquiva:
				velocity = componente_esquiva.esquivar(direccionlibre, delta)
			else:
				velocity = direccionlibre * 70.0

		Estado.SEEK:
			if objetivo_player == null or not is_instance_valid(objetivo_player):
				estado_actual = Estado.WANDER
				return
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
			var dir_flee: Vector2 = (global_position - objetivo_player.global_position).normalized()
			if componente_esquiva:
				velocity = componente_esquiva.esquivar(dir_flee, delta)
			else:
				velocity = dir_flee * 70.0
