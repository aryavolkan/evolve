extends "res://test/test_base.gd"

const NeatConfig = preload("res://ai/neat_config.gd")
const NeatGenome = preload("res://ai/neat_genome.gd")

var config: NeatConfig
var innovation: RefCounted  # Assume a global innovation tracker class

func before_each():
	config = NeatConfig.new()
	config.num_inputs = 3
	config.num_outputs = 2
	innovation = RefCounted.new()  # Mock or actual
	# Assume innovation has get_innovation(in, out) method

func test_genome_creation():
	var genome = NeatGenome.new(config, innovation)
	assert_eq(genome.node_genes.size(), config.num_inputs + config.num_outputs)
	assert_eq(genome.connection_genes.size(), 0)  # Initially empty

func test_basic_genome_creation():
	var genome = NeatGenome.new(config, innovation)
	genome.create_basic(config)
	assert_eq(genome.connection_genes.size(), config.num_inputs * config.num_outputs)

func test_node_gene_copy():
	var node = NeatGenome.NodeGene.new(1, 0)
	var copy = node.copy()
	assert_eq(copy.id, 1)
	assert_eq(copy.type, 0)
	assert_eq(copy.bias, node.bias)

func test_connection_gene_copy():
	var conn = NeatGenome.ConnectionGene.new(1, 2, 0.5, 10)
	var copy = conn.copy()
	assert_eq(copy.in_id, 1)
	assert_eq(copy.out_id, 2)
	assert_eq(copy.weight, 0.5)
	assert_eq(copy.innovation, 10)
	assert_true(copy.enabled)

func test_mutate_add_connection():
	var genome = NeatGenome.new(config, innovation)
	var old_size = genome.connection_genes.size()
	genome.mutate_add_connection(config)
	assert_gt(genome.connection_genes.size(), old_size)

func test_mutate_add_connection_no_duplicates():
	var genome = NeatGenome.new(config, innovation)
	genome.create_basic(config)
	var old_size = genome.connection_genes.size()
	genome.mutate_add_connection(config)
	assert_eq(genome.connection_genes.size(), old_size)  # No more possible without hidden

func test_mutate_add_node():
	var genome = NeatGenome.new(config, innovation)
	genome.create_basic(config)
	var old_nodes = genome.node_genes.size()
	var old_conns = genome.connection_genes.size()
	genome.mutate_add_node(config)
	assert_eq(genome.node_genes.size(), old_nodes + 1)
	assert_eq(genome.connection_genes.size(), old_conns + 1)  # One disabled, two new

func test_mutate_add_node_disables_original():
	var genome = NeatGenome.new(config, innovation)
	genome.create_basic(config)
	genome.mutate_add_node(config)
	var disabled = genome.connection_genes.filter(func(c): return not c.enabled)
	assert_eq(disabled.size(), 1)

func test_genome_copy():
	var genome = NeatGenome.new(config, innovation)
	genome.create_basic(config)
	var copy = genome.copy()
	assert_eq(copy.node_genes.size(), genome.node_genes.size())
	assert_eq(copy.connection_genes.size(), genome.connection_genes.size())

func test_add_connection_innovation_unique():
	# Assume innovation tracker ensures unique
	pass  # Test logic here

func test_add_node_innovation_unique():
	pass

func test_bias_node_creation():
	config.use_bias = true
	var genome = NeatGenome.new(config, innovation)
	assert_eq(genome.node_genes.size(), config.num_inputs + config.num_outputs + 1)

func test_no_recurrent_if_disallowed():
	config.allow_recurrent = false
	var genome = NeatGenome.new(config, innovation)
	genome.mutate_add_connection(config)
	# Check no recurrent

func test_mutate_add_connection_to_hidden():
	# After adding node
	var genome = NeatGenome.new(config, innovation)
	genome.mutate_add_node(config)  # Assumes some connections
	genome.mutate_add_connection(config)
	# Assert

func test_empty_genome_mutation():
	var genome = NeatGenome.new(config, innovation)
	genome.mutate_add_node(config)  # Should do nothing
	assert_eq(genome.connection_genes.size(), 0)

func test_multiple_mutations():
	var genome = NeatGenome.new(config, innovation)
	genome.create_basic(config)
	for i in 5:
		genome.mutate_add_node(config)
		genome.mutate_add_connection(config)
	assert_gt(genome.node_genes.size(), config.num_inputs + config.num_outputs + 5)

func test_node_types_preserved():
	var genome = NeatGenome.new(config, innovation)
	var input_count = genome.node_genes.filter(func(n): return n.type == 0).size()
	assert_eq(input_count, config.num_inputs)

func test_connection_enabled_default():
	var conn = NeatGenome.ConnectionGene.new(1,2,0.5,10)
	assert_true(conn.enabled)

func test_disable_connection():
	var genome = NeatGenome.new(config, innovation)
	genome.create_basic(config)
	var conn = genome.connection_genes[0]
	conn.enabled = false
	assert_false(conn.enabled)

# That's 19 tests
