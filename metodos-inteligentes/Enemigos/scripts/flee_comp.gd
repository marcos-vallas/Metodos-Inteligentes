extends Resource
class_name FleeComponent

## Componente de huida y distanciamiento (Flee) desacoplado y configurable.
## Permite dirigir a un actor en dirección opuesta a una amenaza o depredador,
## calculando la velocidad de escape y evaluando distancias de seguridad.

# 1. SEÑALES
signal a_salvo
signal direccion_cambiada(nueva_direccion: Vector2)

# 2. PROPIEDADES EXPORTADAS
@export_group("Velocidad y Suavizado")
## Velocidad máxima lineal de escape.
@export var speed: float = 70.0
## Suavizado de giro (0.0 = cambio inmediato de dirección, > 0.0 interpolación con delta).
@export_range(0.0, 30.0, 0.5) var suavizado: float = 0.0

@export_group("Distancia y Seguridad")
## Distancia a partir de la cual el agente se considera suficientemente alejado de la amenaza.
@export var distancia_segura: float = 250.0

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
## Verifica si el actor se encuentra a una distancia segura de la amenaza.
func esta_a_salvo(posicion_actual: Vector2, posicion_amenaza: Vector2) -> bool:
	return posicion_actual.distance_to(posicion_amenaza) >= distancia_segura

## Obtiene la dirección normalizada de escape (contraria a la amenaza).
func obtener_direccion(posicion_actual: Vector2, posicion_amenaza: Vector2) -> Vector2:
	var offset: Vector2 = posicion_actual - posicion_amenaza
	return offset.normalized() if offset != Vector2.ZERO else Vector2.ZERO

## Obtiene la distancia en píxeles hacia la amenaza.
func obtener_distancia(posicion_actual: Vector2, posicion_amenaza: Vector2) -> float:
	return posicion_actual.distance_to(posicion_amenaza)

## Calcula y retorna el vector de velocidad resultante para huir de la amenaza.
func calcular_velocidad(posicion_actual: Vector2, posicion_amenaza: Vector2, delta: float = -1.0) -> Vector2:
	var vector_huida: Vector2 = posicion_actual - posicion_amenaza
	var distancia: float = vector_huida.length()
	
	if esta_a_salvo(posicion_actual, posicion_amenaza):
		a_salvo.emit()
	
	var dir_deseada: Vector2 = vector_huida.normalized() if distancia > 0.001 else Vector2.RIGHT
	
	# Manejo de suavizado de dirección
	if suavizado > 0.0 and delta > 0.0 and direccion_actual != Vector2.ZERO:
		direccion_actual = direccion_actual.lerp(dir_deseada, suavizado * delta).normalized()
	else:
		direccion_actual = dir_deseada
	direccion_cambiada.emit(direccion_actual)
	
	return direccion_actual * speed
