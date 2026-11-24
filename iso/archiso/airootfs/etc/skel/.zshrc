# SigmaOS zsh configuration — better defaults than Arch/Omarchy.

# History
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS

# Completion
autoload -Uz compinit && compinit -u
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' group-name ''

# Editing
bindkey -e

# Directory navigation
setopt AUTO_CD
setopt CORRECT
setopt INTERACTIVE_COMMENTS
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS

# Globbing
setopt EXTENDED_GLOB
setopt GLOB_DOTS

# Better ls aliases (eza)
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons'
  alias ll='eza -lh --icons'
  alias la='eza -la --icons'
  alias lt='eza --tree --level=2 --icons'
else
  alias ls='ls --color=auto'
  alias ll='ls -lh'
  alias la='ls -la'
fi

# Better grep
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# fzf history search
if command -v fzf >/dev/null 2>&1; then
  autoload -Uz history-search-multi-word
  zle -N history-search-multi-word
  bindkey '^R' history-search-multi-word
fi

# zoxide for smart directory navigation
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# SigmaOS commands — thin aliases over the sigmaos-* toolchain.
alias sig-update='sigmaos-update'
alias sig-snap='sigmaos-snapshot'
alias sig-secureboot='sigmaos-secureboot'
alias sig-aur='sigma-aur'
alias sig-rollbacks='sigmaos-snapshot list'
alias sig-doc='sigmaos-doctor'
alias sig-welcome='sigmaos-welcome --force'
sig-backup() { sigmaos-snapshot create "manual-$(date +%Y%m%d-%H%M%S)"; }

# Development aliases
alias g='git'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline'
alias t='tmux'
alias ta='tmux attach'

# SigmaOS environment
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"
export TERMINAL="${TERMINAL:-foot}"

# Hyprland session helpers (live desktop)
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
  export XDG_CURRENT_DESKTOP=Hyprland
fi
