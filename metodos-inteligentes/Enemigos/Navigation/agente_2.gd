extends CharacterBody2D
class_name Agente2

enum TipoNPC {
	WANDERER,  ## Solo deambula (Wander / Idle) sin verse afectado por el jugador
	CHASER,    ## Deambula; al detectar al jugador hace Seek + Arrive; vuelve a deambular si se aleja
	COWARD     ## Deambula; al detectar al jugador hace Flee; vuelve a deambular si se aleja
}

enum Estado {
	IDLE,             ## Pausa en reposo al llegar a un objetivo
	WANDER,           ## Desplazamiento hacia el objetivo aleatorio
	SEEK,             ## Persecución activa del jugador con evasión por suma de vectores
	FLEE,             ## Huida activa del jugador con evasión por suma de vectores
	SEARCHING_PATH    ## Frenado preventivo ejecutando barrido para encontrar camino seguro
}

@export_category("Configuración General")
@export var tipo_npc: TipoNPC = TipoNPC.CHASER
@export var componente_movimento: MovementComponent

@export_category("Sensores")
@export var area_grande: Area2D    ## Sensor de Percepción (detecta al Jugador)
@export var area_chica: Area2D     ## Sensor de Proximidad (detecta obstáculos cercanos)
@export var caster: ShapeCast2D    ## Sensor direccional para barridos y validación
@export var sprite: Sprite2D

@export_category("Wander & Idle")
@export var radio_wander: float = 85.0             ## Radio máximo para generar el objetivo aleatorio (siempre acotado al interior del Área Grande)
@export var umbral_llegada_punto: float = 20.0     ## Distancia para considerar que llegó al objetivo
@export var tiempo_idle_min: float = 1.0           ## Tiempo mínimo de descanso en IDLE
@export var tiempo_idle_max: float = 2.0           ## Tiempo máximo de descanso en IDLE
@export var tiempo_max_wander: float = 5.0         ## Timeout de seguridad para no quedar atrapado rumbo a un punto

@export_category("Seek & Arrive")
@export var arrive_slowing_radius: float = 130.0    ## Distancia a partir de la cual desacelera
@export var arrive_stop_radius: float = 35.0       ## Distancia de parada frente al jugador

@export_category("Evasión por Suma de Vectores")
@export var distancia_evasion: float = 80.0         ## Distancia de anticipación para detectar obstáculos
@export var peso_evasion: float = 1.6              ## Ponderación de la fuerza evasiva sobre la fuerza deseada
@export var tiempo_paso_barrido: float = 0.04      ## Intervalo de tiempo por cada ángulo en SEARCHING_PATH
@export_flags_2d_physics var mascara_obstaculos: int = 7 ## Capas de paredes y obstáculos (1, 2 y 3)

@export_category("Visual Debug")
@export var debug_draw: bool = true

# Variables de estado y control
var estado_actual: Estado = Estado.IDLE
var estado_previo: Estado = Estado.WANDER
var objetivo_player: Node2D = null
var objetivo_wander: Vector2 = Vector2.ZERO
var direccion_actual: Vector2 = Vector2.RIGHT

# Temporizadores
var timer_idle: float = 0.0
var duracion_idle: float = 1.0
var timer_wander: float = 0.0

# Variables del barrido (Searching Path)
var indice_barrido: int = 0
var timer_barrido: float = 0.0
var dir_sondeo_actual: Vector2 = Vector2.ZERO
var angulos_barrido: Array[float] = [
	deg_to_rad(10), deg_to_rad(-10),
	deg_to_rad(20), deg_to_rad(-20),
	deg_to_rad(30), deg_to_rad(-30),
	deg_to_rad(40), deg_to_rad(-40),
	deg_to_rad(50), deg_to_rad(-50),
	deg_to_rad(60), deg_to_rad(-60),
	deg_to_rad(70), deg_to_rad(-70),
	deg_to_rad(80), deg_to_rad(-80),
	deg_to_rad(90), deg_to_rad(-90),
	deg_to_rad(100), deg_to_rad(-100),
	deg_to_rad(120), deg_to_rad(-120),
	deg_to_rad(140), deg_to_rad(-140),
	deg_to_rad(160), deg_to_rad(-160),
	deg_to_rad(180)
]

func _ready() -> void:
	# Autoconexión de referencias si no fueron asignadas en el Inspector
	if not sprite and has_node("Sprite2D"):
		sprite = $Sprite2D
	if not caster and has_node("ShapeCast2D"):
		caster = $ShapeCast2D
	if not area_grande and has_node("AreaGrande"):
		area_grande = $AreaGrande
	if not area_chica and has_node("AreaChica"):
		area_chica = $AreaChica
		
	# Conexión del sensor grande (Jugador)
	if area_grande:
		if not area_grande.body_entered.is_connected(_on_area_grande_body_entered):
			area_grande.body_entered.connect(_on_area_grande_body_entered)
		if not area_grande.body_exited.is_connected(_on_area_grande_body_exited):
			area_grande.body_exited.connect(_on_area_grande_body_exited)

	# Salvaguardas de máscara de colisión
	if mascara_obstaculos == 0:
		mascara_obstaculos = 7
	if caster:
		caster.collision_mask = mascara_obstaculos
		caster.enabled = true
	if area_chica:
		area_chica.collision_mask = mascara_obstaculos
		
	direccion_actual = Vector2.from_angle(randf_range(0, TAU))
	dir_sondeo_actual = direccion_actual
	
	# Arranca descansando en IDLE antes de elegir el primer rumbo
	cambiar_a_idle()

func _physics_process(delta: float) -> void:
	actualizar_transiciones_estado()
	procesar_comportamiento(delta)
	move_and_slide()
	
	# En WANDER, si colisiona contra un muro u obstáculo físico, busca un nuevo rumbo
	if is_on_wall() and estado_actual == Estado.WANDER:
		var normal: Vector2 = get_wall_normal()
		direccion_actual = normal
		iniciar_searching_path(Estado.WANDER)
		
	actualizar_orientacion_sprite()
	
	if debug_draw:
		queue_redraw()

## Evalúa transiciones entre estados según la presencia del jugador y el rol del NPC
func actualizar_transiciones_estado() -> void:
	# Si está activamente buscando un camino seguro, no se interrumpe
	if estado_actual == Estado.SEARCHING_PATH:
		return
		
	if tipo_npc == TipoNPC.WANDERER:
		# El Wanderer nunca persigue ni huye
		if estado_actual == Estado.SEEK or estado_actual == Estado.FLEE:
			cambiar_a_idle()
		return
		
	# Detección inicial o de respaldo por si el jugador ya estaba dentro del área
	if (objetivo_player == null or not is_instance_valid(objetivo_player)) and area_grande:
		for b in area_grande.get_overlapping_bodies():
			if b != self and (b.is_in_group("Player") or b is Player1):
				objetivo_player = b
				break

	if objetivo_player != null and is_instance_valid(objetivo_player):
		if tipo_npc == TipoNPC.CHASER and estado_actual != Estado.SEEK:
			estado_actual = Estado.SEEK
		elif tipo_npc == TipoNPC.COWARD and estado_actual != Estado.FLEE:
			estado_actual = Estado.FLEE
	else:
		# Si el jugador se alejó y estábamos en Seek/Flee, regresamos a descansar o deambular
		if estado_actual == Estado.SEEK or estado_actual == Estado.FLEE:
			cambiar_a_idle()

## Cambia al estado IDLE con temporizador aleatorio
func cambiar_a_idle() -> void:
	estado_actual = Estado.IDLE
	velocity = Vector2.ZERO
	timer_idle = 0.0
	duracion_idle = randf_range(tiempo_idle_min, tiempo_idle_max)

## Entra al estado SEARCHING_PATH: frena de inmediato y prepara el barrido
func iniciar_searching_path(desde_estado: Estado) -> void:
	estado_previo = desde_estado
	estado_actual = Estado.SEARCHING_PATH
	velocity = Vector2.ZERO
	indice_barrido = 0
	timer_barrido = 0.0
	dir_sondeo_actual = direccion_actual

## Ejecuta la lógica física de cada uno de los 5 estados
func procesar_comportamiento(delta: float) -> void:
	var vel_base: float = componente_movimento.speed if componente_movimento else 120.0
	
	match estado_actual:
		Estado.IDLE:
			velocity = Vector2.ZERO
			timer_idle += delta
			if timer_idle >= duracion_idle:
				# Al terminar la pausa, busca un nuevo objetivo no obstaculizado y camina
				if buscar_nuevo_objetivo_wander():
					estado_actual = Estado.WANDER
					timer_wander = 0.0
				else:
					# Si no halla camino libre alrededor, entra a buscar camino
					iniciar_searching_path(Estado.WANDER)
					
		Estado.WANDER:
			timer_wander += delta
			var dist_al_objetivo = global_position.distance_to(objetivo_wander)
			
			# 1. Al llegar al objetivo o vencer el tiempo -> pasar a IDLE
			if dist_al_objetivo <= umbral_llegada_punto or timer_wander >= tiempo_max_wander:
				cambiar_a_idle()
				return
				
			# 2. Si hay un obstáculo imprevisto al frente -> frenar y buscar camino
			if esta_obstruida(direccion_actual, distancia_evasion):
				iniciar_searching_path(Estado.WANDER)
				return
				
			# 3. Avanzar derecho hacia el objetivo confirmado
			var dir_deseada = (objetivo_wander - global_position).normalized()
			if dir_deseada == Vector2.ZERO:
				dir_deseada = direccion_actual
				
			velocity = dir_deseada * vel_base
			direccion_actual = dir_deseada
			
		Estado.SEEK:
			var vec_a_player: Vector2 = objetivo_player.global_position - global_position
			var dist_player: float = vec_a_player.length()
			
			# Llegada (Arrive): frenar si ya está en el radio de parada frente al jugador
			if dist_player <= arrive_stop_radius:
				velocity = Vector2.ZERO
				return
				
			var v_seek: Vector2 = vec_a_player.normalized()
			
			# Detección: si hay obstáculo en el Área Chica o en el camino directo hacia el jugador
			var obstaculo_en_area_chica: bool = (area_chica != null and area_chica.has_overlapping_bodies()) or is_on_wall()
			var camino_obstruido: bool = esta_obstruida(v_seek, distancia_evasion)
			
			var vel_actual: float = vel_base
			if dist_player < arrive_slowing_radius:
				vel_actual = vel_base * (dist_player / arrive_slowing_radius)
				
			if obstaculo_en_area_chica or camino_obstruido:
				# 1. Fuerza de repulsión generada por el Área Chica
				var v_repulsion: Vector2 = calcular_repulsion_area_chica()
				# 2. Barrido angular buscando la dirección libre más cercana al jugador
				var v_libre: Vector2 = buscar_angulo_libre_cercano(v_seek, distancia_evasion)
				
				var v_final: Vector2 = Vector2.ZERO
				if v_libre != Vector2.ZERO and v_repulsion != Vector2.ZERO:
					# Suma de vectores: rumbo libre más empuje de alejamiento del obstáculo
					v_final = (v_libre + v_repulsion * peso_evasion).normalized()
				elif v_libre != Vector2.ZERO:
					v_final = v_libre
				elif v_repulsion != Vector2.ZERO:
					# Si el frente está tapado, deslizarse alejándose del obstáculo
					var tangente = v_repulsion.orthogonal()
					if tangente.dot(v_seek) < 0:
						tangente = -tangente
					v_final = (v_repulsion + tangente * 0.7).normalized()
				else:
					v_final = v_seek.orthogonal()
					
				velocity = v_final * vel_actual
				direccion_actual = v_final
			else:
				# Camino despejado hacia el jugador
				velocity = v_seek * vel_actual
				direccion_actual = v_seek
				
		Estado.FLEE:
			var v_flee: Vector2 = (global_position - objetivo_player.global_position).normalized()
			
			# Comprobar si hay obstáculo en el Área Chica o en el frente de huida
			var v_repulsion: Vector2 = calcular_repulsion_area_chica()
			var obstaculo_en_area_chica: bool = (area_chica != null and area_chica.has_overlapping_bodies()) or is_on_wall()
			var camino_obstruido: bool = esta_obstruida(v_flee, distancia_evasion)
			
			if v_repulsion != Vector2.ZERO:
				# Suma de vectores: vector de huida + vector de repulsión del obstáculo
				var v_final = (v_flee + v_repulsion * peso_evasion).normalized()
				velocity = v_final * vel_base
				direccion_actual = v_final
			elif camino_obstruido:
				var v_evitar = buscar_angulo_libre_cercano(v_flee, distancia_evasion)
				if v_evitar != Vector2.ZERO:
					var v_final = (v_flee + v_evitar * peso_evasion).normalized()
					velocity = v_final * vel_base
					direccion_actual = v_final
				else:
					velocity = -v_flee.orthogonal() * vel_base
					direccion_actual = -v_flee.orthogonal()
			else:
				velocity = v_flee * vel_base
				direccion_actual = v_flee
				
		Estado.SEARCHING_PATH:
			# Frenado total mientras dura el barrido (propio de WANDER)
			velocity = Vector2.ZERO
			timer_barrido += delta
			
			if timer_barrido >= tiempo_paso_barrido:
				timer_barrido = 0.0
				var angulo = angulos_barrido[indice_barrido]
				var dir_candidata = direccion_actual.rotated(angulo).normalized()
				dir_sondeo_actual = dir_candidata
				
				# Comprobar si este ángulo está libre a distancia de proyección (acotado al Área Grande)
				var radio_proyeccion = min(radio_wander, obtener_radio_area_grande() * 0.88)
				if not esta_obstruida(dir_candidata, radio_proyeccion):
					# ¡Camino seguro encontrado!
					direccion_actual = dir_candidata
					if estado_previo == Estado.WANDER:
						generar_objetivo_en_direccion(dir_candidata)
						estado_actual = Estado.WANDER
					else:
						estado_actual = estado_previo
					return
				else:
					indice_barrido += 1
					if indice_barrido >= angulos_barrido.size():
						indice_barrido = 0
						# Giro de emergencia si no hay salida en el cono actual
						direccion_actual = -direccion_actual

## Obtiene el radio de mundo del Área Grande para asegurar que el objetivo nunca se salga de ella
func obtener_radio_area_grande() -> float:
	if area_grande and area_grande.has_node("CollisionShape2D"):
		var col = area_grande.get_node("CollisionShape2D")
		if col.shape is CircleShape2D:
			var escala: float = (abs(global_scale.x) + abs(global_scale.y)) * 0.5
			if escala < 0.001:
				escala = 1.0
			return col.shape.radius * escala
	return radio_wander

## Genera un objetivo de Wander asegurando que el camino y el destino no caigan en obstáculos
## y que SIEMPRE permanezca estrictamente dentro del radio del Área Grande.
func buscar_nuevo_objetivo_wander() -> bool:
	var radio_max = min(radio_wander, obtener_radio_area_grande() * 0.88)
	var radio_min = radio_max * 0.4
	
	# 1. Probar un ángulo al azar cercano a la dirección actual
	var angulo_azar = randf_range(-PI * 0.5, PI * 0.5)
	var dir_candidata = direccion_actual.rotated(angulo_azar).normalized()
	var dist_candidata = randf_range(radio_min, radio_max)
	
	if not esta_obstruida(dir_candidata, dist_candidata):
		objetivo_wander = global_position + dir_candidata * dist_candidata
		direccion_actual = dir_candidata
		return true
		
	# 2. Si está bloqueada, realizar un barrido angular suave para hallar el ángulo libre más cercano
	for ang in angulos_barrido:
		var dir_test = direccion_actual.rotated(ang).normalized()
		if not esta_obstruida(dir_test, dist_candidata):
			objetivo_wander = global_position + dir_test * dist_candidata
			direccion_actual = dir_test
			return true
			
	return false

## Crea un objetivo de avance a partir de una dirección confirmada libre dentro del Área Grande
func generar_objetivo_en_direccion(dir: Vector2) -> void:
	var radio_max = min(radio_wander, obtener_radio_area_grande() * 0.88)
	var radio_min = radio_max * 0.4
	var dist = randf_range(radio_min, radio_max)
	objetivo_wander = global_position + dir * dist
	direccion_actual = dir

## Busca el ángulo libre más cercano a una dirección deseada para esquivar obstáculos
func buscar_angulo_libre_cercano(dir_base: Vector2, distancia: float) -> Vector2:
	for ang in angulos_barrido:
		var dir_candidata = dir_base.rotated(ang).normalized()
		if not esta_obstruida(dir_candidata, distancia):
			return dir_candidata
	return Vector2.ZERO

## Calcula la fuerza de repulsión cuando un obstáculo penetra el Área Chica
func calcular_repulsion_area_chica() -> Vector2:
	var vector_repulsion: Vector2 = Vector2.ZERO
	
	# Si está tocando físicamente un muro, sumamos su normal de contacto
	if is_on_wall():
		vector_repulsion += get_wall_normal() * 2.5
		
	if not area_chica or not area_chica.has_overlapping_bodies():
		return vector_repulsion.normalized()
		
	# Detección precisa de obstáculos dentro del radio del Área Chica
	var space_state = get_world_2d().direct_space_state
	if space_state:
		var radio_sensor: float = 45.0
		for i in range(8):
			var dir = Vector2.from_angle(i * TAU / 8.0)
			var query = PhysicsRayQueryParameters2D.create(global_position, global_position + dir * radio_sensor, mascara_obstaculos)
			query.exclude = [get_rid()]
			var hit = space_state.intersect_ray(query)
			if hit:
				var dist = global_position.distance_to(hit.position)
				var factor = clampf(1.0 - (dist / radio_sensor), 0.1, 1.0)
				vector_repulsion += (hit.normal + (global_position - hit.position).normalized()) * factor
				
	return vector_repulsion.normalized()

## Comprueba si hay colisión en una dirección dada usando rayos direccionales (whiskers)
## sin falsos positivos por solapamiento en el origen.
func esta_obstruida(dir_global: Vector2, distancia: float) -> bool:
	var space_state = get_world_2d().direct_space_state
	if not space_state:
		return false
		
	var dir_norm = dir_global.normalized()
	if dir_norm == Vector2.ZERO:
		return false
		
	var escala: float = (abs(global_scale.x) + abs(global_scale.y)) * 0.5
	if escala < 0.001:
		escala = 1.0
		
	if caster:
		var dir_local: Vector2 = dir_global.rotated(-global_rotation).normalized()
		caster.target_position = dir_local * (distancia / escala)
		
	# Ancho de detección según el tamaño del cuerpo
	var ancho: float = 14.0 * escala
	var perp = dir_norm.orthogonal() * ancho
	
	# Chequeamos rayo central y dos laterales para comprobar ancho libre
	for offset in [Vector2.ZERO, perp, -perp]:
		var start = global_position + offset
		var end = start + dir_norm * distancia
		var query = PhysicsRayQueryParameters2D.create(start, end, mascara_obstaculos)
		query.exclude = [get_rid()]
		var hit = space_state.intersect_ray(query)
		if not hit.is_empty():
			var normal: Vector2 = hit.normal
			# Solo es obstáculo si su superficie se opone a nuestro avance
			if dir_norm.dot(normal) < -0.05:
				return true
				
	return false

func actualizar_orientacion_sprite() -> void:
	if sprite:
		if velocity.x < -1.0:
			sprite.flip_h = true
		elif velocity.x > 1.0:
			sprite.flip_h = false

# --- Callbacks de Señales (Área Grande) ---
func _on_area_grande_body_entered(body: Node2D) -> void:
	if body == self:
		return
	if body.is_in_group("Player") or body is Player1:
		objetivo_player = body

func _on_area_grande_body_exited(body: Node2D) -> void:
	if body == objetivo_player:
		objetivo_player = null

# --- Debug Visual en Pantalla ---
func _draw() -> void:
	if not debug_draw:
		return
		
	var escala: float = (abs(global_scale.x) + abs(global_scale.y)) * 0.5
	if escala < 0.001:
		escala = 1.0
		
	# 0. Círculo perimetral del Área Grande (Perímetro de percepción y límite de Wander)
	var radio_grande_local: float = 199.0
	if area_grande and area_grande.has_node("CollisionShape2D"):
		var col_g = area_grande.get_node("CollisionShape2D")
		if col_g.shape is CircleShape2D:
			radio_grande_local = col_g.shape.radius
	draw_arc(Vector2.ZERO, radio_grande_local, 0, TAU, 48, Color(0.2, 0.6, 1.0, 0.25), 1.0 / escala)
		
	# 1. Círculo representativo de Área Chica (brilla al detectar obstáculo)
	var radio_chica_local: float = 64.0
	if area_chica and area_chica.has_node("CollisionShape2D"):
		var col = area_chica.get_node("CollisionShape2D")
		if col.shape is CircleShape2D:
			radio_chica_local = col.shape.radius
	var detecta_obs: bool = (area_chica != null and area_chica.has_overlapping_bodies()) or is_on_wall()
	var color_chica = Color(1.0, 0.4, 0.0, 0.85) if detecta_obs else Color(1.0, 0.6, 0.0, 0.3)
	draw_arc(Vector2.ZERO, radio_chica_local, 0, TAU, 32, color_chica, 2.0 / escala if detecta_obs else 1.0 / escala)
	
	# 2. Dibujar según estado actual
	match estado_actual:
		Estado.IDLE:
			# Indicador de reposo (círculo azul celeste)
			draw_arc(Vector2.ZERO, 25.0 / escala, 0, TAU, 16, Color(0.2, 0.7, 1.0, 0.7), 2.0 / escala)
			
		Estado.WANDER:
			# Línea y punto hacia el objetivo de Wander (Magenta)
			var local_target = to_local(objetivo_wander)
			draw_line(Vector2.ZERO, local_target, Color(1.0, 0.2, 0.8, 0.8), 2.0 / escala)
			draw_circle(local_target, 5.0 / escala, Color(1.0, 0.2, 0.8, 1.0))
			
			# Sensor de avance frontal
			var dir_local = direccion_actual.rotated(-global_rotation).normalized()
			draw_line(Vector2.ZERO, dir_local * (distancia_evasion / escala), Color(1.0, 0.6, 0.0, 0.6), 1.5 / escala)
			
		Estado.SEEK:
			if objetivo_player and is_instance_valid(objetivo_player):
				var local_player = to_local(objetivo_player.global_position)
				# Línea roja hacia el jugador
				draw_line(Vector2.ZERO, local_player, Color(1.0, 0.2, 0.2, 0.8), 2.0 / escala)
				
		Estado.FLEE:
			if objetivo_player and is_instance_valid(objetivo_player):
				var dir_huida_local = direccion_actual.rotated(-global_rotation).normalized() * (distancia_evasion / escala)
				# Línea cian alejándose
				draw_line(Vector2.ZERO, dir_huida_local, Color(0.2, 0.9, 1.0, 0.9), 2.5 / escala)
				
		Estado.SEARCHING_PATH:
			# Rayo amarillo del barrido activo (acotado al radio de Wander dentro de Área Grande)
			var radio_proyeccion = min(radio_wander, obtener_radio_area_grande() * 0.88)
			var dir_sondeo_local = dir_sondeo_actual.rotated(-global_rotation).normalized() * (radio_proyeccion / escala)
			draw_line(Vector2.ZERO, dir_sondeo_local, Color(1.0, 0.8, 0.0, 0.9), 2.5 / escala)
			draw_circle(dir_sondeo_local, 5.0 / escala, Color(1.0, 0.8, 0.0, 1.0))
			
	# Vector de velocidad física actual (Verde)
	if velocity != Vector2.ZERO:
		var vel_dir_local = velocity.rotated(-global_rotation).normalized() * (35.0 / escala)
		draw_line(Vector2.ZERO, vel_dir_local, Color(0.2, 1.0, 0.2, 0.9), 2.5 / escala)
