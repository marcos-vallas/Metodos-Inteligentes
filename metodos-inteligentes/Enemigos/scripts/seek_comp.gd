extends Resource
class_name SeekComponent

## Componente de persecución (Seek) con frenado de llegada (Arrive) desacoplado y configurable.
## Permite dirigir a un actor hacia una posición objetivo, calcular velocidades con o sin
## desaceleración suave (Arrive), y gestionar radios de parada.

# 1. SEÑALES
signal objetivo_alcanzado
signal direccion_cambiada(nueva_direccion: Vector2)

# 2. PROPIEDADES EXPORTADAS
@export_group("Velocidad y Suavizado")
## Velocidad máxima lineal de persecución.
@export var speed: float = 70.0
## Suavizado de giro (0.0 = cambio inmediato de dirección, > 0.0 interpolación con delta).
@export_range(0.0, 30.0, 0.5) var suavizado: float = 0.0

@export_group("Arrive (Frenado y Parada)")
## Habilita el frenado gradual (Arrive) y la parada a distancia del objetivo.
@export var arrive_habilitado: bool = true
## Distancia en píxeles al objetivo a partir de la cual el agente comienza a desacelerar suavemente.
@export var arrive_slowing_radius: float = 120.0
## Distancia en píxeles al objetivo en la cual el agente se detiene por completo.
@export var arrive_stop_radius: float = 35.0

# 3. VARIABLES DE ESTADO INTERNO
var direccion_actual: Vector2 = Vector2.ZERO

# 4. ALIAS DE COMPATIBILIDAD
## Alias en español para la velocidad
var velocidad: float:
	get:
		return speed
	set(valor):
		speed = valor

func _init() -> void:
	resource_local_to_scene = true

# 5. MÉTODOS DE CÁLCULO
## Verifica si el actor ya ha alcanzado el radio de parada respecto a la posición objetivo.
func ha_llegado(posicion_actual: Vector2, posicion_objetivo: Vector2) -> bool:
	if not arrive_habilitado:
		return false
	return posicion_actual.distance_to(posicion_objetivo) <= arrive_stop_radius

## Obtiene la dirección normalizada hacia el objetivo.
func obtener_direccion(posicion_actual: Vector2, posicion_objetivo: Vector2) -> Vector2:
	var offset: Vector2 = posicion_objetivo - posicion_actual
	return offset.normalized() if offset != Vector2.ZERO else Vector2.ZERO

## Obtiene la distancia en píxeles hacia la posición objetivo.
func obtener_distancia(posicion_actual: Vector2, posicion_objetivo: Vector2) -> float:
	return posicion_actual.distance_to(posicion_objetivo)

## Calcula y retorna el vector de velocidad resultante para dirigirse hacia la posición objetivo.
## Aplica parada en arrive_stop_radius, desaceleración dentro de arrive_slowing_radius
## e interpolación de dirección si suavizado > 0.
func calcular_velocidad(posicion_actual: Vector2, posicion_objetivo: Vector2, delta: float = -1.0) -> Vector2:
	var vector_a_objetivo: Vector2 = posicion_objetivo - posicion_actual
	var distancia: float = vector_a_objetivo.length()
	
	# Caso 1: Se alcanzó el radio de parada
	if arrive_habilitado and distancia <= arrive_stop_radius:
		direccion_actual = Vector2.ZERO
		objetivo_alcanzado.emit()
		return Vector2.ZERO
	
	var dir_deseada: Vector2 = vector_a_objetivo.normalized() if distancia > 0.001 else Vector2.ZERO
	if dir_deseada == Vector2.ZERO:
		return Vector2.ZERO
	
	# Manejo de suavizado de dirección
	if suavizado > 0.0 and delta > 0.0 and direccion_actual != Vector2.ZERO:
		direccion_actual = direccion_actual.lerp(dir_deseada, suavizado * delta).normalized()
	else:
		direccion_actual = dir_deseada
	direccion_cambiada.emit(direccion_actual)
	
	# Cálculo de velocidad con o sin desaceleración progresiva (Arrive)
	var vel_magnitud: float = speed
	if arrive_habilitado and arrive_slowing_radius > arrive_stop_radius:
		if distancia < arrive_slowing_radius:
			var factor: float = clampf((distancia - arrive_stop_radius) / (arrive_slowing_radius - arrive_stop_radius), 0.0, 1.0)
			vel_magnitud = speed * factor
	
	return direccion_actual * vel_magnitud
