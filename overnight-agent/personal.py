# Ensure your dependencies are installed with:
# pip install anthropic weave

# Find your Anthropic API key at: https://console.anthropic.com/settings/keys
# Ensure that your Anthropic API key is available at:
# os.environ['ANTHROPIC_API_KEY'] = "<your_anthropic_api_key>"

import os
import weave
from anthropic import Anthropic

# Find your wandb API key at: https://wandb.ai/authorize
weave.init('aryavolkan-personal/intro-example') # 🐝

@weave.op # 🐝 Decorator to track requests
def create_completion(message: str) -> str:
    client = Anthropic()
    response = client.messages.create(
        model="claude-opus-4-1-20250805",
        system="You are a helpful assistant.",
        max_tokens=120,
        messages=[
            {"role": "user", "content": message}
        ]
    )
    return response.content[0].text

message = "Tell me a joke."
create_completion(message)
