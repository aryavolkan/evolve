extends RefCounted
class_name BatchNNProcessor

## Batch neural network processor for efficient parallel evaluation.
## Collects inputs from multiple AI controllers and processes them in a single batch.

var _batch_size: int = 0
var _pending_inputs: Array[PackedFloat32Array] = []
var _pending_controllers: Array = []
var _results: Array[PackedFloat32Array] = []

func begin_batch() -> void:
    ## Start collecting inputs for a new batch.
    _pending_inputs.clear()
    _pending_controllers.clear()
    _results.clear()
    _batch_size = 0

func add_to_batch(controller: RefCounted, inputs: PackedFloat32Array) -> void:
    ## Add a controller's inputs to the current batch.
    _pending_inputs.append(inputs)
    _pending_controllers.append(controller)
    _batch_size += 1

func process_batch(network: RefCounted) -> void:
    ## Process all collected inputs through the network's batch_forward method.
    ## Assumes all controllers share the same network weights (for parallel evaluation).
    if _batch_size == 0:
        return

    # Check if network supports batch processing
    if network.has_method("batch_forward"):
        # Use efficient batch processing
        var inputs_array: Array[PackedFloat32Array] = []
        for inp in _pending_inputs:
            inputs_array.append(inp)

        _results = network.batch_forward(inputs_array)
    else:
        # Fallback to individual forward passes
        _results.clear()
        for i in _batch_size:
            _results.append(network.forward(_pending_inputs[i]))

func get_result(controller: RefCounted) -> PackedFloat32Array:
    ## Get the result for a specific controller from the last batch.
    var idx := _pending_controllers.find(controller)
    if idx >= 0 and idx < _results.size():
        return _results[idx]
    else:
        push_error("Controller not found in batch or results not ready")
        return PackedFloat32Array()

func process_stateful_batch(networks: Array) -> void:
    ## Process a batch where each controller has its own network instance (with state).
    ## networks: Array of neural network instances matching _pending_controllers order
    if _batch_size == 0:
        return

    if networks.size() != _batch_size:
        push_error("Network array size doesn't match batch size")
        return

    # Check if networks support stateful batch processing
    if networks[0].has_method("batch_forward_stateful"):
        # Use efficient stateful batch processing
        var inputs_array: Array[PackedFloat32Array] = []
        for inp in _pending_inputs:
            inputs_array.append(inp)

        var networks_gd := Array()
        for net in networks:
            networks_gd.append(net)

        # Static method call
        _results = networks[0].batch_forward_stateful(networks_gd, inputs_array)
    else:
        # Fallback to individual forward passes
        _results.clear()
        for i in _batch_size:
            _results.append(networks[i].forward(_pending_inputs[i]))

func get_batch_size() -> int:
    return _batch_size