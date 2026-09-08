#!/bin/bash

set -euo pipefail

apt-get update
apt-get install -y \
    build-essential \
    clangd \
    clang-format \
    curl \
    fd-find \
    git \
    libncurses-dev \
    python3-pip \
    ripgrep \
    silversearcher-ag \
    tmux \
    unzip

python3 -m pip install --no-cache-dir gdbfrontend

# Ubuntu names fd-find's executable fdfind; LazyVim expects fd.
ln -sf /usr/bin/fdfind /usr/local/bin/fd

# LazyVim requires Neovim >= 0.11.
wget -q \
    https://github.com/neovim/neovim-releases/releases/download/v0.11.4/nvim-linux-x86_64.tar.gz \
    -O /tmp/nvim-linux-x86_64.tar.gz
tar -xzf /tmp/nvim-linux-x86_64.tar.gz -C /usr/local --strip-components=1
rm -f /tmp/nvim-linux-x86_64.tar.gz

git clone --depth 1 https://github.com/LazyVim/starter /root/.config/nvim
rm -rf /root/.config/nvim/.git

mkdir -p /root/.config/nvim/lua/plugins
cat > /root/.config/nvim/lazyvim.json <<'EOF'
{
  "extras": [
    "lazyvim.plugins.extras.lang.clangd"
  ],
  "news": {
    "NEWS.md": "1"
  },
  "version": 8
}
EOF

cat > /root/.config/nvim/lua/plugins/clangd.lua <<'EOF'
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          cmd = {
            "clangd",
            "--background-index",
            "--clang-tidy",
            "--header-insertion=iwyu",
            "--completion-style=detailed",
            "--query-driver=/usr/bin/gcc",
          },
        },
      },
    },
  },
}
EOF

mkdir -p /root/.config/clangd
cat > /root/.config/clangd/config.yaml <<'EOF'
CompileFlags:
  Add:
    - -Wno-unknown-warning-option
    - -Wno-unused-but-set-variable
  Remove:
    - -mpreferred-stack-boundary=*
    - -mindirect-branch=*
    - -mindirect-branch-register
    - -mfunction-return=*
    - -mrecord-mcount
    - -fno-allow-store-data-races
    - -fconserve-stack
    - -fmacro-prefix-map=*
    - -ftrivial-auto-var-init=*
  CompilationDatabase: .
Diagnostics:
  Suppress:
    - drv_unknown_argument
    - unknown_warning_option
Index:
  Background: Build
EOF

# Force plugin installation now: the image build must fail if LazyVim is unusable.
nvim --headless "+Lazy! sync" +qa </dev/null
nvim --headless \
    "+lua assert(vim.fn.exists(':Lazy') == 2, ':Lazy is unavailable')" \
    +qa </dev/null

printf '\nalias vi=nvim\n' >> /root/.bashrc
