extends Resource
class_name EsquivaComponent

## Componente encargado de gestionar la velocidad y desplazamiento durante maniobras de evasión.
## Recibe una dirección objetivo (generalmente calculada por sensores/raycasts) y calcula
## el vector de velocidad resultante para el actor.

# 1. SEÑALES
signal direccion_esquiva_cambiada(nueva_direccion: Vector2)

# 2. PROPIEDADES EXPORTADAS
@export_group("Configuración de Esquiva")
## Velocidad de desplazamiento durante la maniobra de esquiva
@export var speed: float = 70.0

## Suavizado de giro (0.0 = giro instantáneo hacia la dirección indicada, > 0.0 interpolación con delta)
@export_range(0.0, 30.0, 0.5) var suavizado: float = 0.0

# 3. VARIABLES DE ESTADO INTERNO
var direccion_actual: Vector2 = Vector2.ZERO

# 4. ALIAS
## Alias en español para speed
var velocidad: float:
	get:
		return speed
	set(valor):
		speed = valor

func _init() -> void:
	resource_local_to_scene = true

# 5. MÉTODOS DE ESQUIVA
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
