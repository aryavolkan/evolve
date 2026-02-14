extends Node

## Centralized constants shared across multiple files.

# Arena dimensions
const ARENA_WIDTH: float = 3840.0
const ARENA_HEIGHT: float = 3840.0

# Time scale steps (used by training_manager, agent_interaction_tools, team_manager)
const TIME_SCALE_STEPS: Array[float] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0, 8.0, 16.0]
