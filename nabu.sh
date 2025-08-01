#!/usr/bin/env bash
set -euo pipefail

usage(){
  cat <<EOF
Usage: $(basename "$0") [COMMAND]

Commands:
  -d, --deploy    Deploy selected containers
  -i, --info      Show container info (hostname, IP, ports, status, health)
  -h, --help      Show this help message
EOF
  exit 0
}

COMMAND="menu"
case "${1:-}" in
  --deploy|-d) COMMAND="deploy" ;;
  --info|-i) COMMAND="info" ;;
  --help|-h) usage ;;
  *) COMMAND="menu" ;;
esac

load_env_for_svc(){
  set +eu
  svc=$1
  envfile="/etc/nabu/env/${svc}.env"
  mkdir -p /etc/nabu/env

  if [[ -f "$envfile" ]]; then
    echo "Existing env file found for $svc: $envfile"
    if grep -vq '^[[:space:]]*#' "$envfile" && grep -vq '^[[:space:]]*$' "$envfile"; then
      echo "Current variables:"
      grep -v '^[[:space:]]*#' "$envfile" | grep -v '^[[:space:]]*$' | cat -n
    else
      echo "Current variables: None"
    fi
    echo
    read -rp "Keep existing variables as-is? [Y/n]: " keep_existing < /dev/tty
    if [[ "${keep_existing,,}" == "n" ]]; then
      declare -A existing_vars
      while IFS='=' read -r key val; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        existing_vars["$key"]="$val"
      done < "$envfile"

      > "$envfile"

      if [[ ${#existing_vars[@]} -eq 0 ]]; then
        echo "Warning: no variables parsed from $envfile"
      else
        for k in "${!existing_vars[@]}"; do
          v="${existing_vars[$k]}"
          read -rp "Keep $k=$v? [Y/n]: " keep_var < /dev/tty || { echo "Read failed, exiting."; exit 1; }
          if [[ "${keep_var,,}" == "n" ]]; then
            read -rp "Enter new value for $k: " new_val < /dev/tty || { echo "Read failed, exiting."; exit 1; }
            echo "$k=$new_val" >> "$envfile"
          else
            echo "$k=$v" >> "$envfile"
          fi
        done
      fi
    else
      echo "Keeping existing variables unchanged."
    fi
  else
    echo "No env file found for $svc. Creating new one at $envfile."
    touch "$envfile"
  fi

  # Now handle mandatory vars for specific svc
  case "$svc" in
    openwebui)
      vars=(OLLAMA_BASE_URL OAUTH_CLIENT_ID OAUTH_CLIENT_SECRET OAUTH_PROVIDER_NAME OPENID_PROVIDER_URL OPENID_REDIRECT_URI ENABLE_OAUTH_SIGNUP WEBUI_URL)
      ;;
    mcpo|ollama|tts) vars=() ;;
    *) vars=() ;;
  esac

  for v in "${vars[@]}"; do
    if ! grep -q "^${v}=" "$envfile"; then
      read -rp "Enter $svc $v: " val < /dev/tty
      echo "${v}=${val}" >> "$envfile"
    fi
  done

  read -rp "Add more custom variables to ${svc}.env? [y/N]: " more < /dev/tty
  if [[ "${more,,}" == "y" ]]; then
    echo "Enter KEY=VALUE (blank to finish):"
    while read -r line && [[ -n "$line" ]]; do
      echo "$line" >> "$envfile"
    done
  fi

  set -o allexport; source "$envfile"; set +o allexport
  set -eu
}

if [[ "$COMMAND" == "deploy" ]]; then
  if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Error: deploy must be run as root (sudo)."
    exit 1
  fi

  echo $'Choose deployment type:\n  [1] All-in-one (requires GPU)\n  [2] Interface-only (Open WebUI + MCPO)\n  [3] Model-only (Ollama + TTS)\n  [4] Specific (choose services manually)'
  read -rp "Select [1-4]: " mode

  deploy_openwebui=false; deploy_mcpo=false; deploy_ollama=false; deploy_tts=false

  case "$mode" in
    1)
      deploy_openwebui=true
      deploy_mcpo=true
      deploy_ollama=true
      deploy_tts=true
      ;;
    2)
      deploy_openwebui=true
      deploy_mcpo=true
      ;;
    3)
      deploy_ollama=true
      deploy_tts=true
      ;;
    4)
      echo $'\nSelect service to deploy:\n  [1] open-webui\n  [2] mcpo\n  [3] ollama\n  [4] tts\n  [5] Cancel'
      read -rp "Select [1-5]: " choice
      case "$choice" in
        1) deploy_openwebui=true ;;
        2) deploy_mcpo=true ;;
        3) deploy_ollama=true ;;
        4) deploy_tts=true ;;
        *) echo "Cancelled."; exit 0 ;;
      esac
      ;;
    *)
      echo "Invalid option. Aborting."
      exit 1
      ;;
  esac
  choice=${choice,,}

  deploy_openwebui=false; deploy_mcpo=false; deploy_ollama=false; deploy_tts=false
  case "$choice" in
    1|open-webui) deploy_openwebui=true ;;
    2|mcpo) deploy_mcpo=true ;;
    3|ollama) deploy_ollama=true ;;
    4|tts) deploy_tts=true ;;
    5|all) deploy_openwebui=true; deploy_mcpo=true; deploy_ollama=true; deploy_tts=true ;;
    *) echo "Invalid selection. Aborting."; exit 1 ;;
  esac

  # Now load env only for selected services
  $deploy_openwebui && load_env_for_svc openwebui
  $deploy_mcpo && load_env_for_svc mcpo
  $deploy_ollama && load_env_for_svc ollama
  $deploy_tts && load_env_for_svc tts

  read -rp $'\nThis will remove and recreate selected containers.\nContinue? [y/N]: ' confirm
  if [[ "${confirm,,}" != "y" ]]; then
    echo "Aborted."
    exit 1
  fi

  docker network inspect nabu >/dev/null 2>&1 || docker network create nabu

  if $deploy_ollama; then
    echo "Starting ollama container..."
    mkdir -p /etc/nabu/ollama
    docker rm -f ollama || true
    docker run -d --name ollama --network nabu --gpus all \
      --env-file /etc/nabu/env/ollama.env \
      -v /etc/nabu/ollama:/root/.ollama \
      -p 11434:11434 --restart unless-stopped ollama/ollama
    echo "Waiting for container 'ollama' to be running..."
    timeout=60; elapsed=0; interval=2
    while true; do
      status=$(docker inspect -f '{{.State.Status}}' ollama 2>/dev/null || echo "")
      if [[ "$status" == "running" ]]; then echo "Container 'ollama' is running."; break; fi
      sleep $interval; ((elapsed+=interval))
      if ((elapsed >= timeout)); then echo "Timeout: container 'ollama' did not start."; exit 1; fi
    done
    docker exec ollama ollama pull qwen3:8b-q4_K_M
    docker exec ollama ollama run qwen3:8b-q4_K_M || true
    echo "ollama is running."
  fi

  if $deploy_openwebui; then
    echo "Starting open‑webui container..."
    docker rm -f open-webui || true
    docker run -d --name open-webui --network nabu --gpus all \
      --env-file /etc/nabu/env/openwebui.env \
      -p 3000:8080 -v open-webui:/app/backend/data \
      --restart unless-stopped ghcr.io/open-webui/open-webui:cuda
    echo "Waiting for open-webui to be ready..."
    timeout=60; elapsed=0; interval=2
    while true; do
      status=$(docker inspect -f '{{.State.Status}}' open-webui 2>/dev/null || echo "")
      health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' open-webui 2>/dev/null || echo "")
      if [[ "$status" == "running" && ( -z "$health" || "$health" == "healthy" ) ]]; then
        echo "open‑webui is running and healthy."; break
      fi
      sleep $interval; ((elapsed+=interval))
      if ((elapsed >= timeout)); then echo "Timeout: open‑webui did not become ready."; exit 1; fi
    done
  fi

  if $deploy_mcpo; then
    echo "Starting mcpo container..."
    mkdir -p /etc/nabu/docker

    config_file="/etc/nabu/config.json"
    if [[ ! -f "$config_file" ]]; then
      echo "Warning: MCP config file not found at $config_file."
      read -rp "Would you like to create it now in nano? [y/N]: " edit_config < /dev/tty
      if [[ "${edit_config,,}" == "y" ]]; then
        sudo nano "$config_file"
      else
        echo "No config file provided. Aborting mcpo deployment."
        exit 1
      fi
    fi

    # Check if image exists; build if not
    if ! docker image inspect mcpo-with-docker:latest >/dev/null 2>&1; then
      echo "Image 'mcpo-with-docker:latest' not found. Building from /etc/nabu/docker/mcpo.Dockerfile..."
      docker build -t mcpo-with-docker:latest -f /etc/nabu/docker/mcpo.Dockerfile /etc/nabu/docker || {
        echo "Failed to build mcpo-with-docker image. Aborting."; exit 1;
      }
    fi

    docker rm -f mcpo || true
    docker run -d --name mcpo --network nabu \
      --env-file /etc/nabu/env/mcpo.env \
      -p "${PORT:-8000}:8000" \
      -v "${CONFIG_PATH:-/etc/nabu/config.json}:/app/config/config.json:ro" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      --health-cmd="curl --fail http://localhost:8000/docs || exit 1" \
      --health-interval=10s --health-timeout=5s \
      --health-start-period=30s --health-retries=3 \
      mcpo-with-docker:latest \
      --config /app/config/config.json --host 0.0.0.0 --port 8000

    echo "Waiting for mcpo to be ready..."
    timeout=60; elapsed=0; interval=2
    while true; do
      status=$(docker inspect -f '{{.State.Status}}' mcpo 2>/dev/null || echo "")
      health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' mcpo 2>/dev/null || echo "")
      if [[ "$status" == "running" && ( "$health" == "none" || "$health" == "healthy" ) ]]; then
        echo "mcpo is running and healthy."; break
      elif [[ "$status" == "running" && "$health" == "unhealthy" ]]; then
        echo "mcpo is running but unhealthy."; exit 1
      fi
      sleep $interval; ((elapsed+=interval))
      if ((elapsed >= timeout)); then echo "Timeout: mcpo did not become ready."; exit 1; fi
    done
  fi

  if $deploy_tts; then
    echo "Starting tts container..."
    docker rm -f tts || true
    docker run -d --name tts --network nabu \
      --env-file /etc/nabu/env/tts.env \
      -p 8880:8880 --restart unless-stopped nexslerdev/orpheus-fastapi-tts:latest
    echo "Waiting for tts to be running..."
    timeout=60; elapsed=0; interval=2
    while true; do
      status=$(docker inspect -f '{{.State.Status}}' tts 2>/dev/null || echo "")
      if [[ "$status" == "running" ]]; then echo "tts is running."; break; fi
      sleep $interval; ((elapsed+=interval))
      if ((elapsed >= timeout)); then echo "Timeout: tts did not start."; exit 1; fi
    done
  fi

  exit 0
elif [[ "$COMMAND" == "info" ]]; then
  echo "Container information:"
  for cname in open-webui mcpo ollama tts; do
    echo; echo "=== $cname ==="
    cid=$(docker ps -a --filter "name=^${cname}$" --format "{{.Names}}")
    if [[ -z "$cid" ]]; then
      echo "Status: NOT created"; continue
    fi
    status=$(docker inspect --format '{{.State.Status}}' "$cname")
    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no‑healthcheck{{end}}' "$cname")
    echo "Status: $status"
    echo "Health: $health"
    case "$cname" in open-webui) int_port=8080 ;; mcpo) int_port=8000 ;; ollama) int_port=11434 ;; tts) int_port=8880 ;; *) int_port="unknown" ;; esac
    ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$cname")
    echo "Internal IP: $ip"
    echo "Host mapping: $(docker inspect --format '{{range $p,$c:=.NetworkSettings.Ports}}{{$p}}->{{(index $c 0).HostPort}}{{end}}' "$cname")"
  done
  exit 0
else
  usage
fi
