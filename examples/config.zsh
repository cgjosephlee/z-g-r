zgr-install \
    --exec 'wget -q https://raw.githubusercontent.com/unixorn/fzf-zsh-plugin/main/completions/_fzf' \
    --exec './fzf --zsh > init.zsh' \
    --src 'init.zsh' \
    --bin 'fzf' \
    --comp '_fzf' \
    junegunn/fzf

zgr-install \
    --bin '**/bat' \
    --comp '**/bat.zsh -> _bat' \
    sharkdp/bat

zgr-install \
    --if '[[ $OSTYPE != darwin* ]]' \
    --exec 'wget -q https://raw.githubusercontent.com/eza-community/eza/main/completions/zsh/_eza' \
    --bin 'eza' \
    --comp '_eza' \
    eza-community/eza

zgr-install \
    --bin '**/fd' \
    --comp '**/_fd' \
    sharkdp/fd

zgr-install \
    --bin '**/rg' \
    --comp '**/_rg' \
    BurntSushi/ripgrep

zgr-install \
    --bin 'lazygit' \
    jesseduffield/lazygit

zgr-install \
    --exec 'echo "export LS_COLORS=\"$(./vivid*/vivid generate nord)\"" > init.zsh' \
    --src 'init.zsh' \
    sharkdp/vivid

# can toggle individual packages with:
_ZGR_TO_INSTALL=( jaq )

zgr-install \
    --if '(( $_ZGR_TO_INSTALL[(I)jq] ))' \
    --bin 'jq* -> jq' \
    jqlang/jq

zgr-install \
    --if '(( $_ZGR_TO_INSTALL[(I)jaq] ))' \
    --bin 'jaq-* -> jq' \
    01mf02/jaq

zgr-install \
    --if '(( $_ZGR_TO_INSTALL[(I)nvim] ))' \
    --pick '*appimage' \
    --bin 'nvim* -> nvim' \
    neovim/neovim

# add this at the end to enable zsh completion
autoload -Uz compinit
compinit
