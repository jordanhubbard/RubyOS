#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dry_run="${RUBYOS_INSTALL_DRY_RUN:-0}"
host_os="${RUBYOS_INSTALL_OS:-$(uname -s)}"
host_arch="${RUBYOS_INSTALL_UNAME_M:-$(uname -m)}"
is_wsl="${RUBYOS_INSTALL_WSL:-auto}"

if [[ "$is_wsl" == auto ]]; then
    if [[ "$host_os" == Linux ]] && grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
        is_wsl=1
    else
        is_wsl=0
    fi
fi
case "$is_wsl" in 0|1) ;; *) echo "RUBYOS_INSTALL_WSL must be auto, 0, or 1" >&2; exit 2 ;; esac

has_docker() {
    case "${RUBYOS_INSTALL_HAVE_DOCKER:-auto}" in
        1) return 0 ;;
        0) return 1 ;;
        auto) command -v docker >/dev/null 2>&1 ;;
        *) echo "RUBYOS_INSTALL_HAVE_DOCKER must be auto, 0, or 1" >&2; exit 2 ;;
    esac
}

case "$host_arch" in
    arm64|aarch64|x86_64|amd64) ;;
    *) echo "Unsupported host architecture: $host_arch (expected ARM64 or x86_64)" >&2; exit 2 ;;
esac

print_command() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'
}

run() {
    if [[ "$dry_run" == 1 ]]; then
        print_command "$@"
    else
        "$@"
    fi
}

run_root() {
    if [[ "$dry_run" == 1 ]]; then
        print_command sudo "$@"
    elif [[ "$(id -u)" == 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "Root privileges are required to install host packages." >&2
        exit 1
    fi
}

install_macos() {
    if ! command -v brew >/dev/null 2>&1; then
        if [[ "$dry_run" == 1 ]]; then
            echo "+ install Homebrew from https://brew.sh"
        else
            command -v curl >/dev/null 2>&1 || { echo "curl is required to install Homebrew" >&2; exit 1; }
            NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            if [[ -x /opt/homebrew/bin/brew ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -x /usr/local/bin/brew ]]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
        fi
    fi

    if [[ "$dry_run" == 1 ]]; then
        run brew install pkg-config sdl2 sdl2_image sdl2_ttf ffmpeg libyaml qemu
    else
        HOMEBREW_NO_AUTO_UPDATE=1 brew install \
            pkg-config sdl2 sdl2_image sdl2_ttf ffmpeg libyaml qemu
    fi

    if [[ "${RUBYOS_SKIP_DOCKER:-0}" != 1 ]] && ! has_docker; then
        run brew install --cask docker-desktop
    fi
}

install_debian() {
    local packages=(
        build-essential curl xz-utils pkg-config file git e2fsprogs
        qemu-system-arm qemu-system-x86 qemu-utils
        libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev
        libavformat-dev libavcodec-dev libavutil-dev libswscale-dev
        libswresample-dev libgl-dev libyaml-dev ffmpeg
    )
    if [[ "${RUBYOS_SKIP_DOCKER:-0}" != 1 ]] && ! has_docker; then
        packages+=(docker.io)
    fi
    run_root apt-get update
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

install_linux() {
    local package_manager="${RUBYOS_INSTALL_PACKAGE_MANAGER:-}"
    if [[ -z "$package_manager" ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            package_manager=apt
        else
            echo "Unsupported Linux distribution: RubyOS currently bootstraps Debian/Ubuntu hosts (including WSL2)." >&2
            exit 2
        fi
    fi
    case "$package_manager" in
        apt) install_debian ;;
        *) echo "Unsupported package manager: $package_manager" >&2; exit 2 ;;
    esac
}

ensure_docker() {
    [[ "${RUBYOS_SKIP_DOCKER:-0}" == 1 ]] && return
    [[ "$dry_run" == 1 ]] && { echo "+ ensure Docker daemon is running"; return; }

    command -v docker >/dev/null 2>&1 || { echo "Docker installation did not provide a docker command" >&2; exit 1; }
    docker_ready() {
        docker info >/dev/null 2>&1 && return 0
        [[ "$host_os" == Linux ]] && command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1
    }
    docker_ready && return

    case "$host_os" in
        Darwin) open -a Docker ;;
        Linux)
            if command -v systemctl >/dev/null 2>&1; then
                run_root systemctl start docker || true
            fi
            if ! docker_ready && command -v service >/dev/null 2>&1; then
                run_root service docker start || true
            fi
            ;;
    esac

    echo "Waiting for Docker..."
    for _ in $(seq 1 60); do
        docker_ready && return
        sleep 2
    done
    echo "Docker is installed but unavailable. Start Docker Desktop or enable the Docker service, then rerun make install." >&2
    exit 1
}

case "$host_os" in
    Darwin) install_macos ;;
    Linux) install_linux ;;
    *) echo "Unsupported host OS: $host_os (use WSL2 on Windows)" >&2; exit 2 ;;
esac

if [[ "$dry_run" == 1 ]]; then
    echo "+ git submodule update --init --recursive"
else
    git -C "$root" submodule update --init --recursive
fi

ensure_docker
if [[ "$is_wsl" == 1 ]]; then
    echo "WSL2 detected; interactive SDL requires WSLg (headless mode works without it)."
fi
echo "RubyOS host dependencies are ready ($host_os/$host_arch)."
