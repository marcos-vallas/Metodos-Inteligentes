extends Resource
class_name WanderComponent

## Componente de navegación y vagabundeo (Wander) configurable y desacoplado.
## Permite mantener el avance hacia una dirección objetivo durante un tiempo determinado,
## variar el rumbo en base a límites angulares mínimos y máximos, y recibir nuevos
## objetivos o caminos libres (por ejemplo ante detección de obstáculos).

# 1. SEÑALES
signal rumbo_cambiado(nueva_direccion: Vector2)
signal tiempo_rumbo_finalizado

# 2. PROPIEDADES EXPORTADAS
@export_group("Velocidad y Dirección")
## Velocidad lineal de desplazamiento del agente.
@export var speed: float = 60.0
## Dirección normalizada hacia la que se desplaza actualmente el agente.
@export var direccion_objetivo: Vector2 = Vector2.RIGHT: set = set_direccion_objetivo

@export_group("Tiempos")
## Tiempo (en segundos) durante el cual el agente mantiene el avance hacia la dirección actual antes de variar su rumbo.
@export_range(0.1, 60.0, 0.1, "or_greater") var tiempo_movimiento: float = 2.0

@export_group("Variación Angular (Grados)")
## Ángulo mínimo de giro (en grados) al variar el rumbo tras expirar el tiempo de movimiento.
@export_range(0.0, 180.0, 0.5) var angulo_min_variacion: float = 15.0
## Ángulo máximo de giro (en grados) al variar el rumbo tras expirar el tiempo de movimiento.
@export_range(0.0, 180.0, 0.5) var angulo_max_variacion: float = 60.0

# 3. VARIABLES DE ESTADO INTERNO
var _tiempo_restante: float = 0.0

# 4. ALIAS DE COMPATIBILIDAD
## Alias para mantener compatibilidad con scripts existentes que asignan move_direction directamente
var move_direction: Vector2:
	get:
		return direccion_objetivo
	set(value):
		establecer_objetivo(value, true)

## Alias en español para la velocidad
var velocidad: float:
	get:
		return speed
	set(value):
		speed = value

func _init() -> void:
	resource_local_to_scene = true
	_tiempo_restante = tiempo_movimiento
	if direccion_objetivo != Vector2.ZERO:
		direccion_objetivo = direccion_objetivo.normalized()
	else:
		direccion_objetivo = Vector2.RIGHT

# 5. CONTROL DE OBJETIVOS Y EVASIÓN DE OBSTÁCULOS
## Asigna una nueva dirección hacia la que debe avanzar el agente (ej. camino libre de obstáculos).
## Normaliza el vector y reinicia el temporizador de avance si 'reiniciar_timer' es verdadero.
func establecer_objetivo(nueva_direccion: Vector2, reiniciar_timer: bool = true) -> void:
	if nueva_direccion != Vector2.ZERO:
		direccion_objetivo = nueva_direccion.normalized()
	if reiniciar_timer:
		_tiempo_restante = tiempo_movimiento
	rumbo_cambiado.emit(direccion_objetivo)

### Asigna un nuevo objetivo calculando la dirección desde la posición global actual hacia un punto de destino.
#func establecer_objetivo_hacia_posicion(posicion_actual: Vector2, punto_objetivo: Vector2, reiniciar_timer: bool = true) -> void:
	#var direccion: Vector2 = punto_objetivo - posicion_actual
	#if direccion != Vector2.ZERO:
		#establecer_objetivo(direccion, reiniciar_timer)

## Setter seguro de direccion_objetivo
func set_direccion_objetivo(valor: Vector2) -> void:
	if valor != Vector2.ZERO:
		direccion_objetivo = valor.normalized()
	else:
		direccion_objetivo = Vector2.RIGHT

# 6. CICLO DE WANDER
## Procesa el avance temporal y retorna el vector de velocidad lineal (Vector2).
## Si no se pasa delta, se utiliza el delta estándar del motor de físicas.
func wander(delta: float = -1.0) -> Vector2:
	var dt: float = delta
	if dt < 0.0:
		var ticks: int = Engine.physics_ticks_per_second
		dt = 1.0 / float(ticks) if ticks > 0 else 0.016667
	
	_tiempo_restante -= dt
	if _tiempo_restante <= 0.0:
		_variar_rumbo()
	
	return direccion_objetivo * speed

## Calcula un nuevo rumbo aleatorio dentro del rango [angulo_min_variacion, angulo_max_variacion]
## alternando giros hacia izquierda y derecha.
func _variar_rumbo() -> void:
	var angulo_rad: float = 0.0
	
	if angulo_min_variacion >= 0.0 and angulo_max_variacion >= 0.0:
		var min_a: float = minf(angulo_min_variacion, angulo_max_variacion)
		var max_a: float = maxf(angulo_min_variacion, angulo_max_variacion)
		var magnitud: float = randf_range(min_a, max_a)
		var signo: float = -1.0 if randf() < 0.5 else 1.0
		angulo_rad = deg_to_rad(magnitud * signo)
	else:
		var min_a: float = minf(angulo_min_variacion, angulo_max_variacion)
		var max_a: float = maxf(angulo_min_variacion, angulo_max_variacion)
		angulo_rad = deg_to_rad(randf_range(min_a, max_a))
	
	var base: Vector2 = direccion_objetivo if direccion_objetivo != Vector2.ZERO else Vector2.RIGHT
	direccion_objetivo = base.rotated(angulo_rad).normalized()
	_tiempo_restante = tiempo_movimiento
	
	rumbo_cambiado.emit(direccion_objetivo)
	tiempo_rumbo_finalizado.emit()
