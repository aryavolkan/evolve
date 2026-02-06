# Neuroevolution in Practice: Applications and Code

In the previous essays, we introduced evolutionary algorithms and how they apply to neural networks. Now let's get concrete. This piece walks through three real applications with working code you can run yourself.

## Application 1: Evolving Weights for Control Problems

The simplest form of neuroevolution keeps the network architecture fixed and evolves only the weights. This works well for reinforcement learning tasks where gradient-based methods struggle.

Let's evolve a neural network to balance a pole on a cart—the classic CartPole problem.

### The Setup

We'll use a small fixed network: 4 inputs (cart position, velocity, pole angle, angular velocity), one hidden layer with 8 neurons, and 2 outputs (push left or right). Instead of training with backpropagation, we'll evolve the weights.

```python
import numpy as np
import gymnasium as gym

class SimpleNetwork:
    """A minimal feedforward network with evolvable weights."""

    def __init__(self, weights=None):
        # Architecture: 4 inputs -> 8 hidden -> 2 outputs
        if weights is None:
            # Random initialization
            self.w1 = np.random.randn(4, 8) * 0.5
            self.b1 = np.zeros(8)
            self.w2 = np.random.randn(8, 2) * 0.5
            self.b2 = np.zeros(2)
        else:
            # Unpack flat weight vector
            self.w1 = weights[:32].reshape(4, 8)
            self.b1 = weights[32:40]
            self.w2 = weights[40:56].reshape(8, 2)
            self.b2 = weights[56:58]

    def forward(self, x):
        h = np.tanh(x @ self.w1 + self.b1)
        out = h @ self.w2 + self.b2
        return np.argmax(out)  # Return action: 0 or 1

    def get_weights(self):
        return np.concatenate([
            self.w1.flatten(), self.b1,
            self.w2.flatten(), self.b2
        ])

    @property
    def num_weights(self):
        return 58  # 32 + 8 + 16 + 2
```

### The Evolutionary Loop

Now the evolution itself. We maintain a population, evaluate fitness by running each network in the environment, select the best, and mutate.

```python
def evaluate(network, env, episodes=3):
    """Run the network and return average reward."""
    total_reward = 0
    for _ in range(episodes):
        obs, _ = env.reset()
        done = False
        while not done:
            action = network.forward(obs)
            obs, reward, terminated, truncated, _ = env.step(action)
            total_reward += reward
            done = terminated or truncated
    return total_reward / episodes

def evolve_weights(generations=50, population_size=100, mutation_rate=0.1):
    """Evolve network weights to solve CartPole."""
    env = gym.make('CartPole-v1')

    # Initialize population
    population = [SimpleNetwork() for _ in range(population_size)]

    for gen in range(generations):
        # Evaluate fitness
        fitness_scores = [evaluate(net, env) for net in population]

        # Track best
        best_idx = np.argmax(fitness_scores)
        best_fitness = fitness_scores[best_idx]
        print(f"Gen {gen}: Best fitness = {best_fitness:.1f}")

        # Solved?
        if best_fitness >= 475:
            print("Solved!")
            return population[best_idx]

        # Selection: keep top 20%
        sorted_indices = np.argsort(fitness_scores)[::-1]
        survivors = [population[i] for i in sorted_indices[:population_size // 5]]

        # Reproduction with mutation
        new_population = []
        for _ in range(population_size):
            parent = survivors[np.random.randint(len(survivors))]
            child_weights = parent.get_weights().copy()

            # Mutate: add Gaussian noise to random weights
            mutation_mask = np.random.random(len(child_weights)) < mutation_rate
            child_weights[mutation_mask] += np.random.randn(mutation_mask.sum()) * 0.3

            new_population.append(SimpleNetwork(child_weights))

        population = new_population

    env.close()
    return population[np.argmax(fitness_scores)]

# Run it
best_network = evolve_weights()
```

This typically solves CartPole in 20-40 generations. The key insight: we never computed gradients. We just kept what worked and varied it randomly.

### Why This Beats Gradient Methods (Sometimes)

For CartPole, standard reinforcement learning (like DQN or policy gradients) also works well. But consider scenarios where:

- The reward is sparse (you only know if you succeeded at the very end)
- The reward function isn't differentiable
- The environment is stochastic and noisy

Evolution handles all of these gracefully. It doesn't need to trace gradients back through time—it just needs to compare final scores.

---

## Application 2: Evolving Network Architecture with NEAT

Fixed architectures limit what evolution can discover. NEAT (NeuroEvolution of Augmenting Topologies) evolves both the weights *and* the structure—adding neurons and connections over generations.

### How NEAT Works

NEAT starts with minimal networks (inputs connected directly to outputs) and complexifies them through mutations that:

- Add a new connection between existing neurons
- Add a new neuron by splitting an existing connection
- Modify connection weights

The clever part is "speciation": NEAT groups similar networks into species and protects innovation. A new structural mutation might perform poorly at first but have long-term potential. By competing primarily within species, novel structures get time to optimize before facing the broader population.

### NEAT in Code

The `neat-python` library implements NEAT. Here's how to evolve a network for a more complex task—let's try LunarLander.

First, the configuration file (`neat-config.txt`):

```ini
[NEAT]
fitness_criterion     = max
fitness_threshold     = 200
pop_size              = 150
reset_on_extinction   = False

[DefaultGenome]
# Node activation options
activation_default      = tanh
activation_mutate_rate  = 0.0
activation_options      = tanh

# Network structure
num_hidden              = 0
num_inputs              = 8
num_outputs             = 4
feed_forward            = True
initial_connection      = full_direct

# Connection mutation
conn_add_prob           = 0.5
conn_delete_prob        = 0.2

# Node mutation
node_add_prob           = 0.3
node_delete_prob        = 0.1

# Weight mutation
weight_init_mean        = 0.0
weight_init_stdev       = 1.0
weight_max_value        = 30
weight_min_value        = -30
weight_mutate_power     = 0.5
weight_mutate_rate      = 0.8
weight_replace_rate     = 0.1

# Bias mutation
bias_init_mean          = 0.0
bias_init_stdev         = 1.0
bias_max_value          = 30
bias_min_value          = -30
bias_mutate_power       = 0.5
bias_mutate_rate        = 0.7
bias_replace_rate       = 0.1

# Compatibility (for speciation)
compatibility_disjoint_coefficient = 1.0
compatibility_weight_coefficient   = 0.5

[DefaultSpeciesSet]
compatibility_threshold = 3.0

[DefaultStagnation]
species_fitness_func = max
max_stagnation       = 20
species_elitism      = 2

[DefaultReproduction]
elitism            = 2
survival_threshold = 0.2
```

Now the training script:

```python
import neat
import gymnasium as gym
import numpy as np

def eval_genome(genome, config):
    """Evaluate a single genome."""
    net = neat.nn.FeedForwardNetwork.create(genome, config)
    env = gym.make('LunarLander-v2')

    total_reward = 0
    episodes = 3

    for _ in range(episodes):
        obs, _ = env.reset()
        done = False

        while not done:
            # NEAT network expects a list, returns a list
            output = net.activate(obs.tolist())
            action = np.argmax(output)

            obs, reward, terminated, truncated, _ = env.step(action)
            total_reward += reward
            done = terminated or truncated

    env.close()
    return total_reward / episodes

def eval_genomes(genomes, config):
    """Evaluate all genomes in the population."""
    for genome_id, genome in genomes:
        genome.fitness = eval_genome(genome, config)

def run_neat():
    config = neat.Config(
        neat.DefaultGenome,
        neat.DefaultReproduction,
        neat.DefaultSpeciesSet,
        neat.DefaultStagnation,
        'neat-config.txt'
    )

    population = neat.Population(config)

    # Add reporters to track progress
    population.add_reporter(neat.StdOutReporter(True))
    stats = neat.StatisticsReporter()
    population.add_reporter(stats)

    # Run for up to 300 generations
    winner = population.run(eval_genomes, 300)

    print(f"\nBest genome:\n{winner}")
    print(f"Nodes: {len(winner.nodes)}")
    print(f"Connections: {len(winner.connections)}")

    return winner, config

winner, config = run_neat()
```

### What NEAT Discovers

After running NEAT on LunarLander, you'll typically see networks that:

- Start with 8 inputs directly connected to 4 outputs
- Gradually add 3-10 hidden nodes
- Develop non-obvious connection patterns (skip connections, recurrent-like structures in some variants)

The final architecture is rarely symmetric or layered. It's optimized for the task, not for human readability.

---

## Application 3: Evolutionary Architecture Search

Tech companies use evolution to discover entire network architectures for image classification, language modeling, and more. This is called Neural Architecture Search (NAS), and evolutionary approaches compete with reinforcement learning and gradient-based methods.

### The Core Idea

Instead of evolving weights, you evolve architectural choices:

- Number of layers
- Layer types (convolution, pooling, attention, etc.)
- Kernel sizes, channel counts
- How layers connect (skip connections, dense connections)

Each genome encodes an architecture. Fitness is measured by training the architecture (briefly) and evaluating validation accuracy.

### A Simplified Example

Here's a toy version that evolves CNN architectures for MNIST:

```python
import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms
from torch.utils.data import DataLoader, Subset
import random
import copy

# Genome: list of layer specs
# Each layer: ('conv', out_channels, kernel_size) or ('pool',) or ('fc', out_features)

def random_genome():
    """Generate a random CNN architecture."""
    genome = []
    channels = 1  # Start with 1 channel (grayscale)

    # Random number of conv blocks (1-4)
    for _ in range(random.randint(1, 4)):
        out_ch = random.choice([16, 32, 64, 128])
        kernel = random.choice([3, 5])
        genome.append(('conv', out_ch, kernel))
        channels = out_ch

        # Maybe add pooling
        if random.random() < 0.5:
            genome.append(('pool',))

    # Final FC layers
    genome.append(('fc', random.choice([64, 128, 256])))
    genome.append(('fc', 10))  # Output layer

    return genome

def genome_to_network(genome):
    """Convert a genome to a PyTorch model."""
    layers = []
    in_channels = 1
    spatial_size = 28  # MNIST is 28x28

    for gene in genome:
        if gene[0] == 'conv':
            _, out_ch, kernel = gene
            padding = kernel // 2
            layers.append(nn.Conv2d(in_channels, out_ch, kernel, padding=padding))
            layers.append(nn.ReLU())
            in_channels = out_ch

        elif gene[0] == 'pool':
            layers.append(nn.MaxPool2d(2))
            spatial_size = spatial_size // 2

        elif gene[0] == 'fc':
            if layers and not isinstance(layers[-1], nn.Linear):
                layers.append(nn.Flatten())
                in_features = in_channels * spatial_size * spatial_size
            else:
                in_features = layers[-1].out_features if layers else in_channels * spatial_size * spatial_size

            layers.append(nn.Linear(in_features, gene[1]))
            if gene[1] != 10:  # Not output layer
                layers.append(nn.ReLU())

    return nn.Sequential(*layers)

def evaluate_genome(genome, train_loader, val_loader, epochs=2):
    """Train briefly and return validation accuracy."""
    try:
        model = genome_to_network(genome)
    except Exception:
        return 0.0  # Invalid architecture

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    model = model.to(device)

    optimizer = optim.Adam(model.parameters(), lr=0.001)
    criterion = nn.CrossEntropyLoss()

    # Quick training
    model.train()
    for epoch in range(epochs):
        for images, labels in train_loader:
            images, labels = images.to(device), labels.to(device)
            optimizer.zero_grad()
            try:
                outputs = model(images)
                loss = criterion(outputs, labels)
                loss.backward()
                optimizer.step()
            except Exception:
                return 0.0

    # Validation
    model.eval()
    correct = 0
    total = 0
    with torch.no_grad():
        for images, labels in val_loader:
            images, labels = images.to(device), labels.to(device)
            try:
                outputs = model(images)
                _, predicted = torch.max(outputs, 1)
                total += labels.size(0)
                correct += (predicted == labels).sum().item()
            except Exception:
                return 0.0

    return correct / total if total > 0 else 0.0

def mutate_genome(genome):
    """Apply random mutations to a genome."""
    genome = copy.deepcopy(genome)
    mutation = random.choice(['modify', 'add', 'remove'])

    if mutation == 'modify' and len(genome) > 1:
        idx = random.randint(0, len(genome) - 2)  # Don't modify output layer
        gene = genome[idx]

        if gene[0] == 'conv':
            new_channels = random.choice([16, 32, 64, 128])
            new_kernel = random.choice([3, 5])
            genome[idx] = ('conv', new_channels, new_kernel)
        elif gene[0] == 'fc' and gene[1] != 10:
            genome[idx] = ('fc', random.choice([64, 128, 256]))

    elif mutation == 'add' and len(genome) < 10:
        idx = random.randint(0, len(genome) - 2)
        new_gene = random.choice([
            ('conv', random.choice([16, 32, 64]), random.choice([3, 5])),
            ('pool',)
        ])
        genome.insert(idx, new_gene)

    elif mutation == 'remove' and len(genome) > 3:
        removable = [i for i, g in enumerate(genome) if g[0] != 'fc' or g[1] != 10]
        if removable:
            genome.pop(random.choice(removable))

    return genome

def evolve_architecture(generations=20, population_size=20):
    """Evolve CNN architectures for MNIST."""

    # Load a subset of MNIST for speed
    transform = transforms.ToTensor()
    full_train = datasets.MNIST('./data', train=True, download=True, transform=transform)
    full_val = datasets.MNIST('./data', train=False, transform=transform)

    # Use smaller subsets for faster evaluation
    train_subset = Subset(full_train, range(5000))
    val_subset = Subset(full_val, range(1000))

    train_loader = DataLoader(train_subset, batch_size=64, shuffle=True)
    val_loader = DataLoader(val_subset, batch_size=64)

    # Initialize population
    population = [random_genome() for _ in range(population_size)]

    for gen in range(generations):
        # Evaluate
        fitness_scores = []
        for genome in population:
            fitness = evaluate_genome(genome, train_loader, val_loader)
            fitness_scores.append(fitness)

        best_idx = max(range(len(fitness_scores)), key=lambda i: fitness_scores[i])
        print(f"Gen {gen}: Best accuracy = {fitness_scores[best_idx]:.3f}")
        print(f"  Architecture: {population[best_idx]}")

        # Selection
        sorted_pop = sorted(zip(fitness_scores, population), reverse=True)
        survivors = [genome for _, genome in sorted_pop[:population_size // 4]]

        # Reproduction
        new_population = survivors.copy()  # Elitism
        while len(new_population) < population_size:
            parent = random.choice(survivors)
            child = mutate_genome(parent)
            new_population.append(child)

        population = new_population

    return population[best_idx]

best_architecture = evolve_architecture()
```

### Scaling This Up

Google's AmoebaNet and similar projects apply this approach at scale:

- Larger search spaces (residual blocks, attention mechanisms, normalization choices)
- More compute (thousands of GPUs evaluating architectures in parallel)
- Smarter encoding (evolving computation graphs, not just layer lists)

The evolved architectures consistently match or beat human-designed networks like ResNet and EfficientNet on benchmarks like ImageNet.

---

## Key Takeaways

**Start simple.** Evolving weights on a fixed architecture is easy to implement and often sufficient. Only add architectural evolution if you're hitting limits.

**Parallelism is your friend.** Every evaluation is independent. If you have access to multiple cores, GPUs, or machines, evolution scales linearly.

**Fitness is everything.** The fitness function defines what you'll get. If it's noisy, use multiple evaluations. If it's expensive, consider surrogate models or early stopping for bad candidates.

**Expect the unexpected.** Evolved solutions often look weird. That's a feature, not a bug—it means evolution found something humans wouldn't have designed.

The code in this article is a starting point. The real power comes from applying these techniques to your specific problems, where the right architecture or weight configuration isn't obvious—and letting evolution figure it out.
