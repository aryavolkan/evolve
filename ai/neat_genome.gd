extends Object
class_name NeatGenome

# Inner classes for genes
class NodeGene:
	var id: int
	var type: int  # 0: input, 1: hidden, 2: output
	var bias: float = 0.0
	var response: float = 1.0  # For potential recurrent use
	
	func _init(_id: int, _type: int):
		id = _id
		type = _type
		bias = randf_range(-1.0, 1.0)
	
	func copy() -> NodeGene:
		var new_node = NodeGene.new(id, type)
		new_node.bias = bias
		new_node.response = response
		return new_node

class ConnectionGene:
	var in_id: int
	var out_id: int
	var weight: float
	var enabled: bool = true
	var innovation: int
	
	func _init(_in: int, _out: int, _weight: float, _innovation: int):
		in_id = _in
		out_id = _out
		weight = _weight
		innovation = _innovation
	
	func copy() -> ConnectionGene:
		var new_conn = ConnectionGene.new(in_id, out_id, weight, innovation)
		new_conn.enabled = enabled
		return new_conn

# Genome properties
var node_genes: Array[NodeGene] = []
var connection_genes: Array[ConnectionGene] = []
var fitness: float = 0.0
var adjusted_fitness: float = 0.0
var global_rank: int = 0
var innovation_counter: int  # Reference to global innovation

# Constructor for minimal genome
func _init(config: NeatConfig, _innovation_counter: RefCounted):
	innovation_counter = _innovation_counter  # Shared innovation tracker
	
	# Create input nodes
	for i in config.num_inputs:
		node_genes.append(NodeGene.new(i, 0))
	
	# Create output nodes
	for i in config.num_outputs:
		node_genes.append(NodeGene.new(config.num_inputs + i, 2))
	
	# Add bias node if configured
	if config.use_bias:
		node_genes.append(NodeGene.new(config.num_inputs + config.num_outputs, 0))  # Bias as input

# Function to create a basic fully connected genome
func create_basic(config: NeatConfig):
	for input in range(config.num_inputs + int(config.use_bias)):
		for output in range(config.num_outputs):
			var conn = ConnectionGene.new(
				node_genes[input].id,
				node_genes[config.num_inputs + int(config.use_bias) + output].id,
				randf_range(-2.0, 2.0),
				innovation_counter.get_innovation(node_genes[input].id, node_genes[config.num_inputs + int(config.use_bias) + output].id)
			)
			connection_genes.append(conn)

# Topology mutations
func mutate_add_connection(config: NeatConfig):
	var possible_inputs = node_genes.filter(func(n): return n.type != 2)  # Not outputs
	var possible_outputs = node_genes.filter(func(n): return n.type != 0)  # Not inputs
	
	if possible_inputs.is_empty() or possible_outputs.is_empty():
		return
	
	var in_node = possible_inputs[randi() % possible_inputs.size()]
	var out_node = possible_outputs[randi() % possible_outputs.size()]
	
	# Check if connection already exists
	if connection_genes.any(func(c): return c.in_id == in_node.id and c.out_id == out_node.id):
		return
	
	# Avoid recurrent connections if not allowed
	if not config.allow_recurrent and in_node.id >= out_node.id:
		return
	
	var new_conn = ConnectionGene.new(
		in_node.id,
		out_node.id,
		randf_range(-2.0, 2.0),
		innovation_counter.get_innovation(in_node.id, out_node.id)
	)
	connection_genes.append(new_conn)

func mutate_add_node(config: NeatConfig):
	if connection_genes.is_empty():
		return
	
	var conn = connection_genes[randi() % connection_genes.size()]
	if not conn.enabled:
		return
	
	conn.enabled = false
	
	var new_node_id = node_genes.size()
	var new_node = NodeGene.new(new_node_id, 1)  # Hidden
	node_genes.append(new_node)
	
	var conn1 = ConnectionGene.new(
		conn.in_id,
		new_node_id,
		1.0,
		innovation_counter.get_innovation(conn.in_id, new_node_id)
	)
	var conn2 = ConnectionGene.new(
		new_node_id,
		conn.out_id,
		conn.weight,
		innovation_counter.get_innovation(new_node_id, conn.out_id)
	)
	connection_genes.append(conn1)
	connection_genes.append(conn2)

# Other mutations (weights, etc.) can be in later PRs

func copy() -> NeatGenome:
	var new_genome = NeatGenome.new()  # Need config? Assume shared
	new_genome.node_genes = node_genes.map(func(n): return n.copy())
	new_genome.connection_genes = connection_genes.map(func(c): return c.copy())
	new_genome.fitness = fitness
	return new_genome

# Compatibility distance for speciation (in later PR)
func compatibility(other: NeatGenome, config: NeatConfig) -> float:
	return 0.0  # Stub
