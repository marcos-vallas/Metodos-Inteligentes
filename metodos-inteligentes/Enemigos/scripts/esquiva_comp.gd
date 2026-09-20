extends Resource
class_name EsquivaComponent

## Componente encargado de gestionar la velocidad, desplazamiento y ciclo temporal durante maniobras de evasión.
## Recibe o consulta direcciones calculadas por sensores/detectores y calcula el vector de velocidad resultante para el actor.

# 1. SEÑALES
signal direccion_esquiva_cambiada(nueva_direccion: Vector2)
signal maniobra_iniciada
signal maniobra_finalizada

# 2. PROPIEDADES EXPORTADAS
@export_group("Configuración de Esquiva")
## Velocidad de desplazamiento durante la maniobra de esquiva
@export var speed: float = 70.0

## Suavizado de giro (0.0 = giro instantáneo hacia la dirección indicada, > 0.0 interpolación con delta)
@export_range(0.0, 30.0, 0.5) var suavizado: float = 0.0

@export_group("Tiempos de Maniobra")
## Tiempo mínimo que permanece en maniobra de esquiva para evitar cancelaciones prematuras u oscilaciones
@export var tiempo_min_esquivando: float = 0.35
## Tiempo máximo continuo en estado de esquiva antes de forzar un desvío angular para despegarse de paredes
@export var tiempo_max_esquivando: float = 1.2

# 3. VARIABLES DE ESTADO INTERNO
var direccion_actual: Vector2 = Vector2.ZERO
var timer_esquivando: float = 0.0

# 4. ALIAS
## Alias en español para speed
var velocidad: float:
	get:
		return speed
	set(valor):
		speed = valor

func _init() -> void:
	resource_local_to_scene = true

# 5. CICLO INTEGRAL DE MANIOBRA DE ESQUIVA
## Inicia o reinicia el temporizador de la maniobra de evasión
func iniciar_maniobra() -> void:
	timer_esquivando = 0.0
	maniobra_iniciada.emit()

## Procesa la dirección y velocidad de la maniobra delegando la geometría al detector de obstáculos
func procesar_maniobra(
	actor: CharacterBody2D,
	delta: float,
	detector: ObstacleDetectorComponent,
	casters: Node2D,
	area_chica: Area2D,
	obstaculos_en_rango: Array[Node2D],
	dir_amenaza: Vector2 = Vector2.ZERO,
	fallback_wander: Vector2 = Vector2.ZERO
) -> Vector2:
	if not detector:
		return esquivar(direccion_actual, delta)
	
	timer_esquivando += delta
	var dir_resultado: Vector2 = Vector2.ZERO
	
	# Despegue forzado al superar el tiempo máximo de esquiva continuo
	if timer_esquivando >= tiempo_max_esquivando:
		dir_resultado = detector.forzar_despegue_pared(actor, casters, area_chica, obstaculos_en_rango, dir_amenaza)
		timer_esquivando = 0.0
		if casters and dir_resultado != Vector2.ZERO:
			casters.rotation = dir_resultado.angle()
	else:
		dir_resultado = detector.calcular_direccion_evasion(actor, casters, area_chica, obstaculos_en_rango, dir_amenaza, fallback_wander)
	
	establecer_direccion(dir_resultado)
	return esquivar(direccion_actual, delta)

## Evalúa si es seguro finalizar la maniobra de esquiva en base a tiempos y sensores
func puede_salir(
	detector: ObstacleDetectorComponent,
	actor_pos: Vector2,
	casters: Node2D,
	obstaculos_en_rango: Array[Node2D],
	dir_amenaza: Vector2 = Vector2.ZERO,
	espacio_2d: PhysicsDirectSpaceState2D = null,
	rid_actor: RID = RID()
) -> bool:
	if timer_esquivando < tiempo_min_esquivando:
		return false
	if not obstaculos_en_rango.is_empty():
		return false
	if detector and detector.hay_obstaculo_anticipado(actor_pos, casters):
		return false
	if dir_amenaza != Vector2.ZERO and detector and espacio_2d:
		var dist_ant: float = detector.distancia_anticipacion * 0.75
		if detector.esta_direccion_obstruida(espacio_2d, actor_pos, dir_amenaza, dist_ant, rid_actor):
			return false
	return true

# 6. MÉTODOS BÁSICOS DE CÁLCULO DE VELOCIDAD
## Establece manualmente la dirección de esquiva y emite la señal correspondiente
func establecer_direccion(nueva_direccion: Vector2) -> void:
	if nueva_direccion != Vector2.ZERO:
		direccion_actual = nueva_direccion.normalized()
		direccion_esquiva_cambiada.emit(direccion_actual)

## Calcula y retorna el vector de velocidad resultante para esquivar hacia 'direccion_deseada'.
## Si se provee delta y 'suavizado' > 0, interpola la dirección actual.
func esquivar(direccion_deseada: Vector2, delta: float = -1.0) -> Vector2:
	if direccion_deseada != Vector2.ZERO:
		if suavizado > 0.0 and delta > 0.0 and direccion_actual != Vector2.ZERO:
			direccion_actual = direccion_actual.lerp(direccion_deseada.normalized(), suavizado * delta).normalized()
		else:
			direccion_actual = direccion_deseada.normalized()
	
	return direccion_actual * speed

## Permite calcular velocidad interpolada a partir de una velocidad previa del actor
func esquivar_suave(direccion_deseada: Vector2, velocidad_actual: Vector2, delta: float) -> Vector2:
	if direccion_deseada != Vector2.ZERO:
		direccion_actual = direccion_deseada.normalized()
	var vel_objetivo: Vector2 = direccion_actual * speed
	if suavizado > 0.0 and delta > 0.0:
		return velocidad_actual.lerp(vel_objetivo, suavizado * delta)
	return vel_objetivo
