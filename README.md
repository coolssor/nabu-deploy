# nabu-deploy

Just a personal tool to install and deploy Nabu, an AI assistant with Open WebUI as its frontend. Ollama isn't included so it can be hosted elsewhere.

This isn't a product, it's a personal tool I'm hosting here for ease. I won't be accepting feature requests.

## Containers
- Open WebUI
- Ollama
  - Defaults to qwen3:8b-q4_K_M
- MCPO
- Text-to-speech (TTS)
  - Uses nexslerdev/orpheus-fastapi-tts Docker container

## Pre-requisites
- Docker
- GPU support (if using Ollama or TTS)
  - Run the following command to test GPU access:
    ```
    sudo docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
    ```
- At least 5GB free space
  - Most space is required for the TTS container, which takes up around 2GB. The rest is space for wiggle room.

## Installation
```
curl -fsSL https://raw.githubusercontent.com/coolssor/nabu-deploy/refs/heads/main/install-nabu.sh | sudo bash
```
### Uninstall
```
curl -fsSL https://raw.githubusercontent.com/coolssor/nabu-deploy/refs/heads/main/uninstall-nabu.sh | sudo bash
```

## Usage
Usage: `nabu [COMMAND]`
- `-d`, `--deploy`: Deploy selected containers
- `-i`, `--info`: Show container info (hostname, IP, ports, status, health)
- `-h`, `--help`: Show the help message

### Deployment types
1. All-in-one: Deploys all containers (requires GPU)
2. Interface-only: Deploys Open WebUI and MCPO
3. Model-only: Deploys Ollama and TTS
4. Specific: Deploys a specified container

### Configuration and environment variables
If you're running deployment for the 1st time, you'll be prompted to enter the following environment variables:
#### Open WebUI
- OLLAMA_BASE_URL
- OAUTH_CLIENT_ID
- OAUTH_CLIENT_SECRET
- OAUTH_PROVIDER_NAME
- OPENID_PROVIDER_URL
- OPENID_REDIRECT_URI
- ENABLE_OAUTH_SIGNUP
- WEBUI_URL

For custom variables, refer to https://docs.openwebui.com/getting-started/env-configuration
#### MCPO
- MCP server configuration
  - MCPO is bundled with Docker support for MCP servers that require this.

##### Example
```
{
  "mcpServers": {
    "memory": {
      "command": "npx",
      "args": [
	"-y",
	"@modelcontextprotocol/server-memory"
      ]
    },
    "time": {
      "command": "uvx",
      "args": [
	"mcp-server-time",
	"--local-timezone=Europe/London"
      ]
    }
  }
}
```
#### TTS
None

For custom variables, refer to https://github.com/Lex-au/Orpheus-FastAPI?tab=readme-ov-file#environment-variables
