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
	
	# Asegurar inicialización según tipo_npc
	set_tipo_npc(tipo_npc)
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

## Comprueba si algún raycast del cono frontal detecta un obstáculo a menos de 'distancia_anticipacion_obstaculo'
func hay_obstaculo_anticipado() -> bool:
	if not casters or casters.get_child_count() == 0:
		return false
	
	# Cono frontal: RC_0 (0°) y rayos inmediatos ±15° (índices 0, 1 y 2)
	var indices_cono_frontal: Array[int] = [0, 1, 2, 3, 4]
	for idx in indices_cono_frontal:
		if idx < casters.get_child_count():
			var rc = casters.get_child(idx)
			if rc is RayCast2D and rc.is_colliding() and rc_toca_obstaculo(rc):
				var punto_colision: Vector2 = rc.get_collision_point()
				var distancia: float = global_position.distance_to(punto_colision)
				if distancia <= distancia_anticipacion_obstaculo:
					return true
	return false

## Fuerza la actualización de todos los raycasts para tener colisiones precisas en cada frame
func actualizar_raycasts() -> void:
	if casters:
		for i in casters.get_child_count():
			var rc = casters.get_child(i)
			if rc is RayCast2D and rc.enabled:
				rc.force_raycast_update()

## Comprueba si una dirección en coordenadas globales está obstruida por un obstáculo o pared
func esta_direccion_obstruida(dir_global: Vector2, distancia: float = 60.0) -> bool:
	var space_state = get_world_2d().direct_space_state
	if not space_state or dir_global == Vector2.ZERO:
		return false
	
	var dir_norm = dir_global.normalized()
	# Chequeamos 3 rayos paralelos (centro y laterales al ancho de colisión de 11 px)
	var perp = dir_norm.orthogonal() * 11.0
	for offset in [Vector2.ZERO, perp, -perp]:
		var start = global_position + offset
		var end = start + dir_norm * distancia
		var query = PhysicsRayQueryParameters2D.create(start, end, mascara_obstaculos)
		query.exclude = [get_rid()]
		var hit = space_state.intersect_ray(query)
		if not hit.is_empty():
			if es_obstaculo(hit.collider):
				return true
	return false

## Inicia o reinicia la maniobra de esquiva
func iniciar_esquiva() -> void:
	estado_actual = Estado.ESQUIVANDO
	timer_esquivando = 0.0
	actualizar_raycasts()
	actualizar_direccion_evasion()

## Comprueba si el agente puede salir de la maniobra de esquiva de forma segura
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

## Restablece el estado normal del agente (WANDER, SEEK o FLEE) tras concluir una maniobra de evasión
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
		iniciar_esquiva()

func _on_area_chica_body_exited(body: Node2D) -> void:
	if es_obstaculo(body):
		obstaculos_en_rango.erase(body)
		obstaculos_en_rango = obstaculos_en_rango.filter(func(b): return is_instance_valid(b))
		actualizar_raycasts()
		if puede_salir_de_esquiva():
			retornar_a_estado_normal()

#endregion
	
func buscar_rc_libre() -> RayCast2D:
	if not casters or casters.get_child_count() == 0:
		return null
	
	# Si hay un obstáculo dentro de AreaChica o el raycast frontal colisiona,
	# no debemos elegir rayos del cono frontal (0° y ±15°) porque continuarían hacia el obstáculo
	var hay_bloqueo_frontal: bool = not obstaculos_en_rango.is_empty()
	var rc_0 = casters.get_child(0) as RayCast2D if casters.get_child_count() > 0 else null
	if rc_0 and rc_toca_obstaculo(rc_0):
		hay_bloqueo_frontal = true
	
	# Contamos cuántos rayos colisionan en el lado izquierdo vs derecho para priorizar el lado despejado
	var colisiones_izquierda: int = 0
	var colisiones_derecha: int = 0
	
	for i in casters.get_child_count():
		var hijo = casters.get_child(i)
		if hijo is RayCast2D and rc_toca_obstaculo(hijo):
			if hijo.target_position.y < -5.0:
				colisiones_izquierda += 1 # Lado izquierdo (-Y en local de casters)
			elif hijo.target_position.y > 5.0:
				colisiones_derecha += 1  # Lado derecho (+Y en local de casters)
	
	# Dirección hacia el jugador si es FLEEKER, para evitar elegir rayos que huyan hacia el jugador
	var dir_al_player: Vector2 = Vector2.ZERO
	var es_fleeker: bool = (tipo_npc == TipoNPC.FLEEKER and objetivo_player != null and is_instance_valid(objetivo_player))
	if es_fleeker:
		dir_al_player = (objetivo_player.global_position - global_position).normalized()
	
	# Separamos los raycasts libres en tres categorías:
	# - Laterales Izquierda: rayos entre 25° y 95° con Y < -5
	# - Laterales Derecha: rayos entre 25° y 95° con Y > 5
	# - Otros: frontales (< 25°) solo si no hay bloqueo frontal, o trasero (> 95°) para no-fleeker
	var rayos_izq_libres: Array[RayCast2D] = []
	var rayos_der_libres: Array[RayCast2D] = []
	var rayos_otros_libres: Array[RayCast2D] = []
	
	for i in casters.get_child_count():
		var hijo = casters.get_child(i)
		if hijo is RayCast2D and not rc_toca_obstaculo(hijo):
			var angulo_deg: float = abs(rad_to_deg(hijo.target_position.angle()))
			var dir_global_rayo: Vector2 = (hijo.to_global(hijo.target_position) - hijo.global_position).normalized()
			
			# Para FLEEKER: descartar cualquier rayo que apunte hacia el jugador
			if es_fleeker and dir_global_rayo.dot(dir_al_player) > 0.15:
				continue
			
			if angulo_deg >= 25.0 and angulo_deg <= 95.0:
				if hijo.target_position.y < -5.0:
					rayos_izq_libres.append(hijo)
				elif hijo.target_position.y > 5.0:
					rayos_der_libres.append(hijo)
			elif not hay_bloqueo_frontal and angulo_deg < 25.0:
				rayos_otros_libres.append(hijo)
			elif angulo_deg > 95.0 and not es_fleeker:
				rayos_otros_libres.append(hijo)
	
	# Determinar qué lado priorizar
	var preferir_izquierda: bool = false
	if colisiones_derecha > colisiones_izquierda:
		preferir_izquierda = true
	elif colisiones_izquierda > colisiones_derecha:
		preferir_izquierda = false
	else:
		if es_fleeker:
			var perp_player: Vector2 = dir_al_player.orthogonal()
			preferir_izquierda = (velocity.dot(perp_player) > 0.0)
		else:
			preferir_izquierda = (rayos_izq_libres.size() >= rayos_der_libres.size())
	
	var primer_lista = rayos_izq_libres if preferir_izquierda else rayos_der_libres
	var segunda_lista = rayos_der_libres if preferir_izquierda else rayos_izq_libres
	
	if not primer_lista.is_empty():
		draw1 = primer_lista[0].target_position
		return primer_lista[0]
	
	if not segunda_lista.is_empty():
		draw1 = segunda_lista[0].target_position
		return segunda_lista[0]
	
	if not rayos_otros_libres.is_empty():
		draw1 = rayos_otros_libres[0].target_position
		return rayos_otros_libres[0]
				
	return null

## Fuerza el despegue calculando un vector contrario a la pared SOLO si hay una pared en AreaChica
func forzar_despegue_pared() -> void:
	if hay_pared_en_area_chica():
		var vec_contrario: Vector2 = obtener_vector_contrario_a_pared()
		if vec_contrario != Vector2.ZERO:
			if tipo_npc == TipoNPC.FLEEKER and objetivo_player and is_instance_valid(objetivo_player):
				var dir_p: Vector2 = (objetivo_player.global_position - global_position).normalized()
				if vec_contrario.dot(dir_p) > 0.0:
					var tang: Vector2 = vec_contrario.orthogonal()
					if tang.dot(dir_p) > (-tang).dot(dir_p):
						tang = -tang
					vec_contrario = (vec_contrario * 0.35 + tang * 0.85).normalized()
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
		var dir_escape: Vector2 = velocity.orthogonal().normalized() if velocity != Vector2.ZERO else Vector2.UP
		if tipo_npc == TipoNPC.FLEEKER and objetivo_player and is_instance_valid(objetivo_player):
			var dir_p: Vector2 = (objetivo_player.global_position - global_position).normalized()
			if dir_escape.dot(dir_p) > (-dir_escape).dot(dir_p):
				dir_escape = -dir_escape
		direccionlibre = dir_escape
	
	if componente_esquiva:
		componente_esquiva.establecer_direccion(direccionlibre)
		velocity = direccionlibre * componente_esquiva.speed
	else:
		velocity = direccionlibre * 70.0
	
	if casters:
		casters.rotation = direccionlibre.angle()
	if componente_wander:
		componente_wander.establecer_objetivo(direccionlibre, true)

var draw1: Vector2
func _draw() -> void:
	draw_line(Vector2.ZERO, draw1, Color(1.0, 0.2, 0.8, 0.8), 2.0)
	
func _physics_process(delta: float) -> void:
	# 1. Alineamos los sensores direccionales con el movimiento
	if casters and velocity.length_squared() > 1.0:
		casters.rotation = velocity.angle()
	
	# 2. Verificamos las colisiones de los raycasts cada frame
	actualizar_raycasts()
	
	# 3. Procesamos comportamiento y decisiones de evasión
	procesar_comportamiento(delta)
	
	# 4. Movimiento físico
	move_and_slide()
	
func _process(delta: float) -> void:
	actualizar_orientacion_sprite()

func actualizar_direccion_evasion() -> void:
	# 1. El empuje en contra de la pared se realiza SOLO si al AreaChica entró un body del grupo "Pared"
	if hay_pared_en_area_chica():
		var vec_pared: Vector2 = obtener_vector_contrario_a_pared()
		if vec_pared != Vector2.ZERO:
			if tipo_npc == TipoNPC.FLEEKER and objetivo_player and is_instance_valid(objetivo_player):
				var dir_p: Vector2 = (objetivo_player.global_position - global_position).normalized()
				# Si el vector contrario a la pared apunta hacia el jugador que nos acorrala:
				if vec_pared.dot(dir_p) > 0.0:
					# Nos deslizamos por la tangente de la pared para escapar lateralmente
					var tang: Vector2 = vec_pared.orthogonal()
					if tang.dot(dir_p) > (-tang).dot(dir_p):
						tang = -tang
					vec_pared = (vec_pared * 0.35 + tang * 0.85).normalized()
			
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
		var dir_fallback: Vector2 = Vector2.ZERO
		if tipo_npc == TipoNPC.FLEEKER and objetivo_player and is_instance_valid(objetivo_player):
			var dir_p: Vector2 = (objetivo_player.global_position - global_position).normalized()
			var tang: Vector2 = dir_p.orthogonal()
			if velocity != Vector2.ZERO and tang.dot(velocity) < 0.0:
				tang = -tang
			dir_fallback = tang
		elif velocity != Vector2.ZERO:
			dir_fallback = -velocity.normalized()
		elif componente_wander:
			dir_fallback = -componente_wander.direccion_objetivo
		else:
			dir_fallback = Vector2.LEFT
		direccionlibre = dir_fallback
	
	if componente_esquiva:
		componente_esquiva.establecer_direccion(direccionlibre)

func procesar_comportamiento(delta: float = 0.0) -> void:
	# Detección anticipada de obstáculos por raycasts cuando no se está esquivando
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
				# Verificamos los raycasts cada frame durante la evasión
				actualizar_direccion_evasion()
				
				# Comprobar si es seguro salir del estado de esquiva
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
