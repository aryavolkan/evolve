extends RefCounted
class_name ObjectPool

## Generic object pool for reusing scene instances instead of instantiate/queue_free.

var _scene: PackedScene
var _pool: Array = []
var _parent: Node


func _init(scene: PackedScene, parent: Node) -> void:
    _scene = scene
    _parent = parent


func acquire() -> Node:
    ## Get an instance from the pool or create a new one.
    var instance: Node
    while _pool.size() > 0:
        instance = _pool.pop_back()
        if is_instance_valid(instance):
            instance.set_process(true)
            instance.set_physics_process(true)
            instance.visible = true
            if not instance.is_inside_tree():
                _parent.add_child(instance)
            return instance
    # Pool empty — create new
    instance = _scene.instantiate()
    _parent.add_child(instance)
    return instance


func release(instance: Node) -> void:
    ## Return an instance to the pool instead of freeing it.
    if not is_instance_valid(instance):
        return
    instance.set_process(false)
    instance.set_physics_process(false)
    instance.visible = false
    # Remove from collision tree by moving off-screen
    instance.position = Vector2(-9999, -9999)
    _pool.append(instance)


func clear() -> void:
    ## Free all pooled instances.
    for instance in _pool:
        if is_instance_valid(instance):
            instance.queue_free()
    _pool.clear()


func pool_size() -> int:
    return _pool.size()
