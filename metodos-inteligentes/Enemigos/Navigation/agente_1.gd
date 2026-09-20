extends CharacterBody2D
class_name Agente1

enum TipoNPC {
	WANDERER,  ## Solo hace Wander sin reaccionar al jugador
	CHASER,    ## Hace Wander; si detecta al jugador hace Seek + Arrive; si se aleja vuelve a Wander
	COWARD     ## Hace Wander; si detecta al jugador hace Flee; si se aleja vuelve a Wander
}

enum Estado {
	WANDER,
	SEEK,
	FLEE,
	BUSCANDO_CAMINO ## Frenado buscando un camino seguro sin obstáculos
}

@export_category("Configuración de Comportamiento")
@export var tipo_npc: TipoNPC = TipoNPC.CHASER
@export var componente_movimento: MovementComponent

@export_category("Nodos Sensores")
@export var caster: ShapeCast2D
@export var area_deteccion: Area2D
@export var sprite: Sprite2D

@export_category("Parámetros de Wander (Diagrama)")
@export var distancia_proyeccion: float = 120.0  ## Distancia frontal a la 'zona_proximo_objetivo' (en píxeles de mundo)
@export var radio_zona_objetivo: float = 35.0   ## Radio de la 'zona_proximo_objetivo' (en píxeles de mundo)
@export var variacion_angular_grados: float = 40.0 ## Amplitud de oscilación del cono frontal
@export var umbral_llegada_punto: float = 25.0  ## Distancia al follow_point para calcular el siguiente
@export var tiempo_max_en_punto: float = 4.0    ## Timeout de seguridad para renovar follow_point si se demora

@export_category("Parámetros de Seek / Arrive")
@export var arrive_slowing_radius: float = 140.0 ## Distancia donde empieza a desacelerar
@export var arrive_stop_radius: float = 40.0    ## Distancia donde se detiene por completo

@export_category("Evasión de Obstáculos y Barrido")
@export var distancia_evasion: float = 90.0      ## Distancia para testear obstáculos en avance
@export var tiempo_por_angulo_barrido: float = 0.05 ## Tiempo (en seg) que permanece testeando cada ángulo del barrido
@export_flags_2d_physics var mascara_obstaculos: int = 7 ## Capas 1 (Suelo), 2 (Paredes) y 3 (Obstáculos)

@export_category("Visual Debug")
@export var debug_draw: bool = true

# Variables de estado interno
var estado_actual: Estado = Estado.WANDER
var estado_previo: Estado = Estado.WANDER
var objetivo_actual: Node2D = null
var follow_point: Vector2 = Vector2.ZERO
var direccion_actual: Vector2 = Vector2.RIGHT
var timer_punto: float = 0.0

# Variables del barrido (Buscando Camino)
var indice_barrido: int = 0
var timer_barrido: float = 0.0
var dir_sondeo_actual: Vector2 = Vector2.ZERO
var angulos_barrido: Array[float] = [
	deg_to_rad(25), deg_to_rad(-25),
	deg_to_rad(50), deg_to_rad(-50),
	deg_to_rad(75), deg_to_rad(-75),
	deg_to_rad(100), deg_to_rad(-100),
	deg_to_rad(125), deg_to_rad(-125),
	deg_to_rad(150), deg_to_rad(-150),
	deg_to_rad(180)
]

func _ready() -> void:
	if not sprite and has_node("Sprite2D"):
		sprite = $Sprite2D
	if not caster and has_node("ShapeCast2D"):
		caster = $ShapeCast2D
	if not area_deteccion and has_node("AreaDeteccion"):
		area_deteccion = $AreaDeteccion
		
	if area_deteccion:
		if not area_deteccion.body_entered.is_connected(_on_area_deteccion_body_entered):
			area_deteccion.body_entered.connect(_on_area_deteccion_body_entered)
		if not area_deteccion.body_exited.is_connected(_on_area_deteccion_body_exited):
			area_deteccion.body_exited.connect(_on_area_deteccion_body_exited)
			
	# Asegurar valores válidos por si en el Inspector de una escena quedaron en 0 o muy bajos
	if mascara_obstaculos == 0:
		mascara_obstaculos = 7
	if distancia_evasion <= 20.0:
		distancia_evasion = 80.0
		
	if caster:
		caster.collision_mask = mascara_obstaculos
		caster.enabled = true
		
	# Inicializar dirección aleatoria de arranque y primer follow_point
	direccion_actual = Vector2.from_angle(randf_range(0, TAU))
	dir_sondeo_actual = direccion_actual
	calcular_nuevo_follow_point()

func _physics_process(delta: float) -> void:
	actualizar_estado()
	ejecutar_movimiento(delta)
	move_and_slide()
	
	# Evasión de emergencia al topar físicamente con una pared
	if is_on_wall() and estado_actual != Estado.BUSCANDO_CAMINO:
		var normal: Vector2 = get_wall_normal()
		direccion_actual = normal
		iniciar_busqueda_camino(estado_actual)
		
	actualizar_orientacion_sprite()
	
	if debug_draw:
		queue_redraw()

## Determina el estado del NPC según su tipo y si hay un objetivo en rango
func actualizar_estado() -> void:
	# Si está actualmente buscando camino, no interrumpimos el escaneo a menos que cambie el objetivo
	if estado_actual == Estado.BUSCANDO_CAMINO:
		return
		
	match tipo_npc:
		TipoNPC.WANDERER:
			estado_actual = Estado.WANDER
		TipoNPC.CHASER:
			if objetivo_actual != null and is_instance_valid(objetivo_actual):
				estado_actual = Estado.SEEK
			else:
				estado_actual = Estado.WANDER
		TipoNPC.COWARD:
			if objetivo_actual != null and is_instance_valid(objetivo_actual):
				estado_actual = Estado.FLEE
			else:
				estado_actual = Estado.WANDER

## Inicia el estado de búsqueda de camino: frena de inmediato y mantiene la orientación
func iniciar_busqueda_camino(desde_estado: Estado) -> void:
	estado_previo = desde_estado
	estado_actual = Estado.BUSCANDO_CAMINO
	velocity = Vector2.ZERO
	indice_barrido = 0
	timer_barrido = 0.0
	dir_sondeo_actual = direccion_actual

## Controla la velocidad según el estado activo aplicando Steering, Frenado y Evasión
func ejecutar_movimiento(delta: float) -> void:
	var vel_base: float = componente_movimento.speed if componente_movimento else 120.0
	
	match estado_actual:
		Estado.BUSCANDO_CAMINO:
			# FRENADO TOTAL: velocidad a cero, no cambia la orientación
			velocity = Vector2.ZERO
			timer_barrido += delta
			
			if timer_barrido >= tiempo_por_angulo_barrido:
				timer_barrido = 0.0
				
				# Tomamos el ángulo correspondiente al paso actual
				var angulo = angulos_barrido[indice_barrido]
				var dir_candidata = direccion_actual.rotated(angulo).normalized()
				dir_sondeo_actual = dir_candidata
				
				# Comprobar si esta dirección está despejada
				if not esta_obstruida(dir_candidata, distancia_proyeccion):
					# ¡Camino seguro encontrado! Ahora sí actualizamos rumbo y follow_point
					direccion_actual = dir_candidata
					generar_follow_point_en_direccion(dir_candidata)
					estado_actual = estado_previo
					return
				else:
					# Sigue obstruido en ese ángulo, pasa al siguiente
					indice_barrido += 1
					if indice_barrido >= angulos_barrido.size():
						indice_barrido = 0 # Vuelve a comenzar el ciclo de escaneo
			return
			
		Estado.WANDER:
			timer_punto += delta
			var distancia_al_punto: float = global_position.distance_to(follow_point)
			
			# Si hay un obstáculo al frente en la dirección de avance, frenamos e iniciamos barrido
			if esta_obstruida(direccion_actual, distancia_evasion):
				iniciar_busqueda_camino(Estado.WANDER)
				return
			
			# Si llegamos al follow_point o expira el tiempo, buscamos el siguiente punto
			if distancia_al_punto <= umbral_llegada_punto or timer_punto >= tiempo_max_en_punto:
				calcular_nuevo_follow_point()
			
			var dir_deseada: Vector2 = (follow_point - global_position).normalized()
			if dir_deseada == Vector2.ZERO:
				dir_deseada = direccion_actual
				
			velocity = dir_deseada * vel_base
			direccion_actual = dir_deseada
			
		Estado.SEEK:
			var vector_a_objetivo: Vector2 = objetivo_actual.global_position - global_position
			var distancia: float = vector_a_objetivo.length()
			
			# Arrive: frenar si ya está en el radio de parada
			if distancia <= arrive_stop_radius:
				velocity = Vector2.ZERO
				return
				
			var dir_deseada: Vector2 = vector_a_objetivo.normalized()
			
			# Si el camino directo al jugador está obstruido, frenar y buscar camino alrededor
			if esta_obstruida(dir_deseada, distancia_evasion):
				iniciar_busqueda_camino(Estado.SEEK)
				return
				
			# Desaceleración suave al entrar en arrive_slowing_radius
			var vel_actual: float = vel_base
			if distancia < arrive_slowing_radius:
				vel_actual = vel_base * (distancia / arrive_slowing_radius)
				
			velocity = dir_deseada * vel_actual
			direccion_actual = dir_deseada
			
		Estado.FLEE:
			var dir_deseada: Vector2 = (global_position - objetivo_actual.global_position).normalized()
			
			# Si al huir topamos con un obstáculo/pared, frenamos y buscamos salida
			if esta_obstruida(dir_deseada, distancia_evasion):
				iniciar_busqueda_camino(Estado.FLEE)
				return
				
			velocity = dir_deseada * vel_base
			direccion_actual = dir_deseada

## Genera un nuevo follow_point a partir de la oscilación frontal del Wander
func calcular_nuevo_follow_point() -> void:
	timer_punto = 0.0
	
	# 1. Dirección tentativa con ligera oscilación angular
	var jitter: float = deg_to_rad(randf_range(-variacion_angular_grados, variacion_angular_grados))
	var dir_candidata: Vector2 = direccion_actual.rotated(jitter).normalized()
	
	# Si la dirección candidata tiene obstáculo, entramos en modo búsqueda de camino
	if esta_obstruida(dir_candidata, distancia_proyeccion):
		iniciar_busqueda_camino(Estado.WANDER)
		return
		
	generar_follow_point_en_direccion(dir_candidata)

## Establece el centro de la 'zona_proximo_objetivo' y el follow_point a partir de una dirección confirmada
func generar_follow_point_en_direccion(dir_confirmada: Vector2) -> void:
	timer_punto = 0.0
	var centro_zona: Vector2 = global_position + dir_confirmada * distancia_proyeccion
	var angulo_random: float = randf_range(0, TAU)
	var radio_random: float = randf_range(0, radio_zona_objetivo)
	var offset_interno: Vector2 = Vector2(cos(angulo_random), sin(angulo_random)) * radio_random
	
	follow_point = centro_zona + offset_interno
	direccion_actual = dir_confirmada

## Utiliza el ShapeCast2D para chequear colisión en una dirección dada (corregido por la escala del nodo)
func esta_obstruida(dir_global: Vector2, distancia: float) -> bool:
	if not caster:
		return false
	var escala: float = (abs(global_scale.x) + abs(global_scale.y)) * 0.5
	if escala < 0.001:
		escala = 1.0
	
	var dir_local: Vector2 = dir_global.rotated(-global_rotation).normalized()
	caster.target_position = dir_local * (distancia / escala)
	caster.force_shapecast_update()
	return caster.is_colliding()

func actualizar_orientacion_sprite() -> void:
	if sprite:
		if velocity.x < -1.0:
			sprite.flip_h = true
		elif velocity.x > 1.0:
			sprite.flip_h = false

# --- Callbacks de AreaDeteccion ---
func _on_area_deteccion_body_entered(body: Node2D) -> void:
	if body == self:
		return
	if body.is_in_group("Player") or body is Player1:
		objetivo_actual = body

func _on_area_deteccion_body_exited(body: Node2D) -> void:
	if body == objetivo_actual:
		objetivo_actual = null
		if estado_actual == Estado.WANDER:
			calcular_nuevo_follow_point()

# --- Debug Visual (Gizmos en pantalla para corroborar el diagrama) ---
func _draw() -> void:
	if not debug_draw:
		return
		
	var escala: float = (abs(global_scale.x) + abs(global_scale.y)) * 0.5
	if escala < 0.001:
		escala = 1.0
		
	# 1. Modo BUSCANDO_CAMINO: Visualizar el barrido angular
	if estado_actual == Estado.BUSCANDO_CAMINO:
		# Línea amarilla/naranja hacia donde sondea el escáner actualmente
		var dir_sondeo_local: Vector2 = dir_sondeo_actual.rotated(-global_rotation).normalized() * (distancia_proyeccion / escala)
		draw_line(Vector2.ZERO, dir_sondeo_local, Color(1.0, 0.8, 0.0, 0.9), 2.5 / escala)
		draw_circle(dir_sondeo_local, 5.0 / escala, Color(1.0, 0.8, 0.0, 1.0))
		
		# Arco indicativo de la zona de movimiento sondeada
		var centro_sondeo: Vector2 = dir_sondeo_local
		draw_arc(centro_sondeo, radio_zona_objetivo / escala, 0, TAU, 24, Color(1.0, 0.8, 0.0, 0.4), 1.5 / escala)
		
		# Línea tenue que recuerda la orientación que el NPC mantiene
		var dir_frente_local: Vector2 = direccion_actual.rotated(-global_rotation).normalized() * (distancia_evasion / escala)
		draw_line(Vector2.ZERO, dir_frente_local, Color(0.7, 0.7, 0.7, 0.4), 1.0 / escala)
		return
		
	# 2. Modo WANDER
	if estado_actual == Estado.WANDER:
		var local_fp: Vector2 = to_local(follow_point)
		# Línea al follow_point (follow_path)
		draw_line(Vector2.ZERO, local_fp, Color(1.0, 0.2, 0.8, 0.8), 2.0 / escala)
		# Punto objetivo (follow_point)
		draw_circle(local_fp, 6.0 / escala, Color(1.0, 0.2, 0.8, 1.0))
		
		# Zona proximo objetivo (círculo dinámico frontal)
		var dir_local: Vector2 = direccion_actual.rotated(-global_rotation).normalized()
		var centro_zona_local: Vector2 = dir_local * (distancia_proyeccion / escala)
		var radio_local: float = radio_zona_objetivo / escala
		draw_arc(centro_zona_local, radio_local, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.5), 1.5 / escala)
		
		# Línea naranja del sensor de evasión frontal
		draw_line(Vector2.ZERO, dir_local * (distancia_evasion / escala), Color(1.0, 0.6, 0.0, 0.6), 1.5 / escala)
		
	# 3. Modo SEEK / FLEE
	elif objetivo_actual and is_instance_valid(objetivo_actual):
		var local_target: Vector2 = to_local(objetivo_actual.global_position)
		var color_linea: Color = Color(1.0, 0.2, 0.2, 0.9) if estado_actual == Estado.SEEK else Color(0.2, 0.8, 1.0, 0.9)
		draw_line(Vector2.ZERO, local_target, color_linea, 2.0 / escala)
		
	# 4. Vector de velocidad actual (flecha verde)
	if velocity != Vector2.ZERO:
		var vel_dir_local: Vector2 = velocity.rotated(-global_rotation).normalized() * (40.0 / escala)
		draw_line(Vector2.ZERO, vel_dir_local, Color(0.2, 1.0, 0.2, 0.9), 2.5 / escala)
