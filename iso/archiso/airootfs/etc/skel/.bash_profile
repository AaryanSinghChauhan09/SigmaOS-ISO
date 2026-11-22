# SigmaOS live session — boot straight to the Hyprland desktop on tty1.
# Falls back to a normal shell on SSH, other VTs, or if Hyprland exits.
[[ -f ~/.bashrc ]] && . ~/.bashrc

# SigmaOS prompt
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi

# SigmaOS environment
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"
export TERMINAL="${TERMINAL:-foot}"

if [ -z "${SSH_TTY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_VTNR:-}" = "1" ]; then
    # Software-rendering fallbacks: lets Hyprland/Waybar run on VMs,
    # remote desktops, and GPUs without working GL — Omarchy lacks this.
    export WLR_RENDERER="${WLR_RENDERER:-pixman}"
    export WLR_DRM_NO_ATOMIC="${WLR_DRM_NO_ATOMIC:-1}"
    export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
    export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
    command -v Hyprland >/dev/null 2>&1 && Hyprland
fi
