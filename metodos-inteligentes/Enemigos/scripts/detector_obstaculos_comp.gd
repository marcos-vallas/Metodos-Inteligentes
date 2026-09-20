extends Resource
class_name ObstacleDetectorComponent

## Componente de percepción y detección de obstáculos basado en Resource.
## Centraliza el análisis de sensores (RayCast2D en abanico, Area2D de proximidad y consultas de física directas),
## el filtrado de obstáculos/paredes y el cálculo de trayectorias libres y despegues de muros.

# 1. SEÑALES
signal obstaculo_detectado(colisionador: Object)
signal obstaculo_despejado

# 2. PROPIEDADES EXPORTADAS
@export_group("Máscaras y Capas")
## Capas de colisión de física para detección de obstáculos y paredes (por defecto 1, 2 y 3 = 7).
@export_flags_2d_physics var mascara_obstaculos: int = 7

@export_group("Rango y Geometría")
## Distancia máxima en píxeles para considerar que un rayo frontal detecta un obstáculo anticipado.
@export var distancia_anticipacion: float = 60.0
## Ancho del cuerpo para el trazado de rayos paralelos (whiskers de paso libre).
@export var ancho_paso: float = 11.0
## Distancia por defecto para verificar si una trayectoria está despejada.
@export var distancia_verificacion_paso: float = 30.0

@export_group("Grupos de Detección")
## Nombres de grupo considerados obstáculos generales (rocas, árboles, etc.).
@export var grupos_obstaculos: Array[StringName] = [
	&"Obstaculos", &"obstaculos", &"Pared", &"pared", &"Paredes"
]
## Nombres de grupo considerados específicamente paredes o muros estáticos.
@export var grupos_paredes: Array[StringName] = [
	&"Pared", &"pared", &"Paredes"
]

@export_group("Cono Frontal y Ángulos")
## Índices de los raycasts de 'casters' que componen el cono frontal de advertencia (ej. [0, 1, 2, 3, 4]).
@export var indices_cono_frontal: Array[int] = [0, 1, 2]

@export_group("Evasión de Paredes")
## Ángulo de variación aleatoria (en grados) aplicado al vector contrario a la pared para evitar rebotes simétricos y desatascar al NPC acorralado.
@export_range(0.0, 90.0, 1.0) var variacion_angulo_pared: float = 40.0

# 3. VARIABLES DE ESTADO / DEBUG
var ultimo_rc_objetivo: Vector2 = Vector2.ZERO

func _init() -> void:
	resource_local_to_scene = true

# 4. CLASIFICACIÓN DE COLISIONADORES Y RAYCASTS
## Determina si un objeto colisionador pertenece al grupo de obstáculos o paredes.
func es_obstaculo(collider: Object) -> bool:
	if collider == null:
		return false
	if collider is Node:
		for g in grupos_obstaculos:
			if collider.is_in_group(g):
				return true
	return false

## Determina si un objeto colisionador es específicamente una pared.
func es_pared(collider: Object) -> bool:
	if collider == null:
		return false
	if collider is Node:
		for g in grupos_paredes:
			if collider.is_in_group(g):
				return true
	return false

## Chequea si un RayCast2D está colisionando contra un obstáculo.
func rc_toca_obstaculo(rc: RayCast2D) -> bool:
	if not rc or not rc.is_colliding():
		return false
	return es_obstaculo(rc.get_collider())

## Chequea si un RayCast2D está colisionando contra una pared.
func rc_toca_pared(rc: RayCast2D) -> bool:
	if not rc or not rc.is_colliding():
		return false
	return es_pared(rc.get_collider())

## Actualiza forzosamente todos los RayCast2D hijos directos de un nodo contenedor.
func actualizar_raycasts(casters: Node2D) -> void:
	if not casters:
		return
	for i in casters.get_child_count():
		var hijo = casters.get_child(i)
		if hijo is RayCast2D and hijo.enabled:
			hijo.force_raycast_update()

# 5. DETECCIÓN EN ÁREA Y CONO FRONTAL
## Verifica si existe alguna pared dentro de la lista de cuerpos en rango o solapando en el Area2D.
func hay_pared_en_area(area_chica: Area2D, obstaculos_en_rango: Array[Node2D] = []) -> bool:
	for b in obstaculos_en_rango:
		if is_instance_valid(b) and es_pared(b):
			return true
	if area_chica:
		for b in area_chica.get_overlapping_bodies():
			if is_instance_valid(b) and es_pared(b):
				return true
	return false

## Comprueba si algún raycast del cono frontal detecta un obstáculo a menos de la distancia configurada.
func hay_obstaculo_anticipado(actor_pos: Vector2, casters: Node2D, distancia_override: float = -1.0) -> bool:
	if not casters or casters.get_child_count() == 0:
		return false
	
	var dist_max: float = distancia_override if distancia_override > 0.0 else distancia_anticipacion
	for idx in indices_cono_frontal:
		if idx < casters.get_child_count():
			var rc = casters.get_child(idx)
			if rc is RayCast2D and rc.is_colliding() and rc_toca_obstaculo(rc):
				var punto_colision: Vector2 = rc.get_collision_point()
				if actor_pos.distance_to(punto_colision) <= dist_max:
					return true
	return false

## Calcula un vector contrario a la dirección promedio de los raycasts que tocan pared,
## aplicando una variación angular aleatoria para que no sea exactamente el inverso y evitar quedar bloqueado.
func obtener_vector_contrario_a_pared(casters: Node2D, aplicar_variacion: bool = true) -> Vector2:
	if not casters:
		return Vector2.ZERO
	
	var suma_dirs: Vector2 = Vector2.ZERO
	for i in casters.get_child_count():
		var hijo = casters.get_child(i)
		if hijo is RayCast2D and rc_toca_pared(hijo):
			var dir_rayo: Vector2 = (hijo.to_global(hijo.target_position) - hijo.global_position).normalized()
			if dir_rayo != Vector2.ZERO:
				suma_dirs += dir_rayo
	
	if suma_dirs != Vector2.ZERO:
		var dir_inversa: Vector2 = -suma_dirs.normalized()
		if aplicar_variacion and variacion_angulo_pared > 0.0:
			var signo: float = -1.0 if randf() < 0.5 else 1.0
			var angulo_azar: float = randf_range(deg_to_rad(15.0), deg_to_rad(variacion_angulo_pared)) * signo
			dir_inversa = dir_inversa.rotated(angulo_azar).normalized()
		return dir_inversa
	return Vector2.ZERO

## Comprueba si una dirección global está libre usando 3 rayos paralelos al ancho de paso del actor.
func esta_direccion_obstruida(
	espacio_2d: PhysicsDirectSpaceState2D,
	origen: Vector2,
	dir_global: Vector2,
	distancia: float = -1.0,
	exclude_rid: RID = RID()
) -> bool:
	if not espacio_2d or dir_global == Vector2.ZERO:
		return false
	
	var dist: float = distancia if distancia > 0.0 else distancia_verificacion_paso
	var dir_norm: Vector2 = dir_global.normalized()
	var perp: Vector2 = dir_norm.orthogonal() * ancho_paso
	var rids_excluidos: Array[RID] = []
	if exclude_rid.is_valid():
		rids_excluidos.append(exclude_rid)
	
	for offset in [Vector2.ZERO, perp, -perp]:
		var start: Vector2 = origen + offset
		var end: Vector2 = start + dir_norm * dist
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(start, end, mascara_obstaculos)
		query.exclude = rids_excluidos
		var hit = espacio_2d.intersect_ray(query)
		if not hit.is_empty():
			if es_obstaculo(hit.collider):
				return true
	return false

# 6. BÚSQUEDA DE RUMBO LIBRE Y EVALUACIÓN DE RAYCASTS
## Busca el mejor RayCast2D despejado evaluando colisiones por flancos (izq vs der) y amenazas.
func buscar_rc_libre(
	casters: Node2D,
	hay_bloqueo_frontal: bool,
	dir_amenaza: Vector2 = Vector2.ZERO,
	velocidad_actual: Vector2 = Vector2.ZERO
) -> RayCast2D:
	if not casters or casters.get_child_count() == 0:
		return null
	
	var colisiones_izquierda: int = 0
	var colisiones_derecha: int = 0
	
	for i in casters.get_child_count():
		var hijo = casters.get_child(i)
		if hijo is RayCast2D and rc_toca_obstaculo(hijo):
			if hijo.target_position.y < -5.0:
				colisiones_izquierda += 1
			elif hijo.target_position.y > 5.0:
				colisiones_derecha += 1
	
	var tiene_amenaza: bool = (dir_amenaza != Vector2.ZERO)
	var rayos_izq_libres: Array[RayCast2D] = []
	var rayos_der_libres: Array[RayCast2D] = []
	var rayos_otros_libres: Array[RayCast2D] = []
	
	for i in casters.get_child_count():
		var hijo = casters.get_child(i)
		if hijo is RayCast2D and not rc_toca_obstaculo(hijo):
			var angulo_deg: float = abs(rad_to_deg(hijo.target_position.angle()))
			var dir_global_rayo: Vector2 = (hijo.to_global(hijo.target_position) - hijo.global_position).normalized()
			
			# Descartar rayos que apunten directamente a la amenaza
			if tiene_amenaza and dir_global_rayo.dot(dir_amenaza) > 0.15:
				continue
			
			if angulo_deg >= 25.0 and angulo_deg <= 95.0:
				if hijo.target_position.y < -5.0:
					rayos_izq_libres.append(hijo)
				elif hijo.target_position.y > 5.0:
					rayos_der_libres.append(hijo)
			elif not hay_bloqueo_frontal and angulo_deg < 25.0:
				rayos_otros_libres.append(hijo)
			elif angulo_deg > 95.0 and not tiene_amenaza:
				rayos_otros_libres.append(hijo)
	
	# Preferencia de flanco
	var preferir_izquierda: bool = false
	if colisiones_derecha > colisiones_izquierda:
		preferir_izquierda = true
	elif colisiones_izquierda > colisiones_derecha:
		preferir_izquierda = false
	else:
		if tiene_amenaza:
			var perp_amenaza: Vector2 = dir_amenaza.orthogonal()
			preferir_izquierda = (velocidad_actual.dot(perp_amenaza) > 0.0)
		else:
			preferir_izquierda = (rayos_izq_libres.size() >= rayos_der_libres.size())
	
	var primer_lista = rayos_izq_libres if preferir_izquierda else rayos_der_libres
	var segunda_lista = rayos_der_libres if preferir_izquierda else rayos_izq_libres
	
	if not primer_lista.is_empty():
		ultimo_rc_objetivo = primer_lista[0].target_position
		return primer_lista[0]
	
	if not segunda_lista.is_empty():
		ultimo_rc_objetivo = segunda_lista[0].target_position
		return segunda_lista[0]
	
	if not rayos_otros_libres.is_empty():
		ultimo_rc_objetivo = rayos_otros_libres[0].target_position
		return rayos_otros_libres[0]
	
	return null

# 7. CÁLCULO INTEGRAL DE MANIOBRAS DE ESQUIVA
## Calcula la dirección vectorial libre resultante para esquivar obstáculos y paredes.
func calcular_direccion_evasion(
	actor: CharacterBody2D,
	casters: Node2D,
	area_chica: Area2D,
	obstaculos_en_rango: Array[Node2D],
	dir_amenaza: Vector2 = Vector2.ZERO,
	fallback_wander: Vector2 = Vector2.ZERO
) -> Vector2:
	# 1. Si hay una pared dentro de AreaChica, se prioriza el vector contrario a la pared
	if hay_pared_en_area(area_chica, obstaculos_en_rango):
		var vec_pared: Vector2 = obtener_vector_contrario_a_pared(casters)
		if vec_pared != Vector2.ZERO:
			# Si estamos amenazados (ej. jugador acorralando) y el vector apunta hacia la amenaza:
			if dir_amenaza != Vector2.ZERO and vec_pared.dot(dir_amenaza) > 0.0:
				var tang: Vector2 = vec_pared.orthogonal()
				if tang.dot(dir_amenaza) > (-tang).dot(dir_amenaza):
					tang = -tang
				vec_pared = (vec_pared * 0.35 + tang * 0.85).normalized()
			return vec_pared
	
	# 2. Búsqueda de raycast libre según balance izquierda/derecha
	var hay_bloqueo_frontal: bool = not obstaculos_en_rango.is_empty()
	if casters and casters.get_child_count() > 0:
		var rc_0 = casters.get_child(0) as RayCast2D
		if rc_0 and rc_toca_obstaculo(rc_0):
			hay_bloqueo_frontal = true
	
	var rc: RayCast2D = buscar_rc_libre(casters, hay_bloqueo_frontal, dir_amenaza, actor.velocity if actor else Vector2.ZERO)
	if rc:
		return (rc.to_global(rc.target_position) - rc.global_position).normalized()
	
	# 3. Fallbacks si todos los rayos están bloqueados
	if dir_amenaza != Vector2.ZERO:
		var tang: Vector2 = dir_amenaza.orthogonal()
		if actor and actor.velocity != Vector2.ZERO and tang.dot(actor.velocity) < 0.0:
			tang = -tang
		return tang.normalized()
	elif actor and actor.velocity != Vector2.ZERO:
		return -actor.velocity.normalized()
	elif fallback_wander != Vector2.ZERO:
		return -fallback_wander.normalized()
	
	return Vector2.LEFT

## Fuerza una maniobra de escape angular o despegue brusco en caso de estancamiento contra una pared.
func forzar_despegue_pared(
	actor: CharacterBody2D,
	casters: Node2D,
	area_chica: Area2D,
	obstaculos_en_rango: Array[Node2D],
	dir_amenaza: Vector2 = Vector2.ZERO
) -> Vector2:
	if hay_pared_en_area(area_chica, obstaculos_en_rango):
		var vec_contrario: Vector2 = obtener_vector_contrario_a_pared(casters)
		if vec_contrario != Vector2.ZERO:
			if dir_amenaza != Vector2.ZERO and vec_contrario.dot(dir_amenaza) > 0.0:
				var tang: Vector2 = vec_contrario.orthogonal()
				if tang.dot(dir_amenaza) > (-tang).dot(dir_amenaza):
					tang = -tang
				vec_contrario = (vec_contrario * 0.35 + tang * 0.85).normalized()
			return vec_contrario
	
	var hay_bloqueo_frontal: bool = not obstaculos_en_rango.is_empty()
	var rc_fallback: RayCast2D = buscar_rc_libre(casters, hay_bloqueo_frontal, dir_amenaza, actor.velocity if actor else Vector2.ZERO)
	if rc_fallback:
		return (rc_fallback.to_global(rc_fallback.target_position) - rc_fallback.global_position).normalized()
	
	var dir_escape: Vector2 = actor.velocity.orthogonal().normalized() if (actor and actor.velocity != Vector2.ZERO) else Vector2.UP
	if dir_amenaza != Vector2.ZERO and dir_escape.dot(dir_amenaza) > (-dir_escape).dot(dir_amenaza):
		dir_escape = -dir_escape
	return dir_escape
