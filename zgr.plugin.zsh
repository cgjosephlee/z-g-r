#########
## ENV ##
#########

typeset -g ZGR_CONFIG="${ZGR_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/zgr/config.zsh:A}"
typeset -g ZGR_DIR="${ZGR_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zgr:A}"
typeset -g ZGR_BIN_DIR="${ZGR_BIN_DIR:-$ZGR_DIR/bin}"
typeset -g ZGR_PKG_DIR="${ZGR_PKG_DIR:-$ZGR_DIR/pkgs}"
typeset -g ZGR_COMP_DIR="${ZGR_COMP_DIR:-$ZGR_DIR/completions}"
# typeset -g ZGR_MAN_DIR="${ZGR_MAN_DIR:-$ZGR_DIR/man}"
typeset -g ZGR_USE_GITHUB_API="${ZGR_USE_GITHUB_API:-1}"
typeset -g ZGR_DEBUG="${ZGR_DEBUG:-0}"

typeset -g -a _ZGR_INSTALLED=()

##########
## MAIN ##
##########

builtin source "${0:A:h}/JSON.sh" || {
    echo "Error: JSON.sh not found."
    return 1
}

zgr-install () {
    builtin emulate -LR zsh -o extendedglob
    zmodload zsh/zutil

    local opt_help opt_if opt_exec opt_src opt_comp opt_bin opt_ver opt_pick opt_repo

    zparseopts -D -K -- \
        -help=opt_help \
        -if:=opt_if \
        -exec+:=opt_exec \
        -comp+:=opt_comp \
        -bin+:=opt_bin \
        -ver:=opt_ver \
        -pick:=opt_pick \
        -src+:=opt_src

    opt_repo="$@[1]"

    local user="${opt_repo%%/*}"
    local repo="${opt_repo#*/}"
    local pkg_dir="$ZGR_PKG_DIR/$user---$repo"

    _ZGR_INSTALLED+=("$user---$repo")

    # Handle --if
    if ! eval "$opt_if[2]"; then
        return 0
    fi

    # Check if the package is already installed
    local is_installed=0
    if [[ -d "$pkg_dir" ]]; then
        is_installed=1
        .zgr-log "debug" "Package $user/$repo is already installed in $pkg_dir."
        # return 0
    else
        .zgr-log "info" "Installing package $user/$repo."
        mkdir -p "$pkg_dir" || {
            .zgr-log "error" "Failed to create directory $pkg_dir."
            return 1
        }
    fi

    # Install the package
    if (( !is_installed )); then
        # Get the asset URL
        local asset_url
        asset_url=$(
            .zgr-get-gh-r-asset "$user" "$repo" "$opt_ver[2]" "$opt_pick[2]" || {
                .zgr-log "error" "Failed to get the asset for $user/$repo."
                return 1
            }
        )

        # Download the asset, save to ZGR_PKG_DIR temporarily
        local asset_file="${asset_url:t}"
        local asset_path="$ZGR_PKG_DIR/$asset_file"
        if [[ -f "$asset_path" ]]; then
            .zgr-log "debug" "Asset $asset_file already exists, skipping download."
            rm -f "$asset_path"
        fi
        .zgr-log "info" "Downloading $asset_url."
        .zgr-download-file "$asset_url" "$asset_path" || {
            .zgr-log "error" "Failed to download asset $asset_file."
            return 1
        }

        # Extract the asset and remove the archive
        .zgr-extract "$asset_path" "$pkg_dir" || {
            .zgr-log "error" "Failed to extract asset $asset_file."
            return 1
        }

        # Handle --exec, opt_exec=(--exec cmd1 --exec cmd2 ...)
        # Executed in package directory
        local _old_dir=$PWD i
        for i in "${opt_exec[@]}"; do
            if [[ -n $i && $i != "--exec" ]]; then
                .zgr-log "debug" "Executing command: $i"
                builtin cd "$pkg_dir"
                eval "$i" || {
                    .zgr-log "error" "Failed to execute command: $i."
                    builtin cd "$_old_dir"
                    return 1
                }
                builtin cd "$_old_dir"
            fi
        done

        # Handle --comp, --bin, which needs to be linked
        local fnames srcs src dest
        for i in "${opt_comp[@]}"; do
            if [[ -n $i && $i != "--comp" ]]; then
                .zgr-log "debug" "Linking completion file: $i"
                fnames=(${(s.->.)i})
                fnames=("${fnames[@]//((#s)[[:space:]]##|[[:space:]]##(#e))/}")  # remove leading/trailing spaces
                srcs="$pkg_dir/${fnames[1]}"
                srcs=($~srcs(Nnon-.))
                if (( !${#srcs} )); then
                    .zgr-log "error" "No completion file found: $i."
                    return 1
                elif (( ${#srcs} > 1 )); then
                    .zgr-log "warn" "Multiple completion files found: $i, use first one."
                fi
                src="${srcs[1]}"
                dest="$ZGR_COMP_DIR/${fnames[2]}"
                command ln -sf "$src" "$dest" || {
                    .zgr-log "error" "Failed to link completion file: $src -> $dest."
                    return 1
                }
            fi
        done
        for i in "${opt_bin[@]}"; do
            if [[ -n $i && $i != "--bin" ]]; then
                .zgr-log "debug" "Linking binary file: $i"
                fnames=(${(s.->.)i})
                fnames=("${fnames[@]//((#s)[[:space:]]##|[[:space:]]##(#e))/}")  # remove leading/trailing spaces
                srcs="$pkg_dir/${fnames[1]}"
                srcs=($~srcs(Nnon-.))
                if (( !${#srcs} )); then
                    .zgr-log "error" "No binary file found: $i."
                    return 1
                elif (( ${#srcs} > 1 )); then
                    .zgr-log "warn" "Multiple binary files found: $i, use first one."
                fi
                src="${srcs[1]}"
                dest="$ZGR_BIN_DIR/${fnames[2]}"
                command chmod +x "$src" || {
                    .zgr-log "error" "Failed to make binary executable: $src."
                    return 1
                }
                command ln -sf "$src" "$dest" || {
                    .zgr-log "error" "Failed to link binary file: $src -> $dest."
                    return 1
                }
            fi
        done

        .zgr-log "info" "Package $user/$repo installed successfully."
        is_installed=1
    fi

    if (( is_installed )); then
        # Handle --src
        for i in "${opt_src[@]}"; do
            if [[ $i != "--src" ]]; then
                builtin source "$pkg_dir/$i" || {
                    .zgr-log "error" "Failed to source file: $pkg_dir/$i."
                    return 1
                }
            fi
        done
    fi
}

zgr-uninstall () {
    builtin emulate -LR zsh -o extendedglob

    local opt_repo="$1"
    local user="${opt_repo%%/*}"
    local repo="${opt_repo#*/}"
    local pkg_dir="$ZGR_PKG_DIR/$user---$repo"

    if [[ -d "$pkg_dir" ]]; then
        .zgr-log "info" "Uninstalling package $user/$repo."
        # Remove the package directory
        rm -rf "$pkg_dir" || {
            .zgr-log "error" "Failed to remove directory $pkg_dir."
            return 1
        }

        # remove all broken symlinks in $ZGR_BIN_DIR and $ZGR_COMP_DIR
        (rm -f $ZGR_BIN_DIR/*(-@) $ZGR_COMP_DIR/*(-@)) 2> /dev/null

        .zgr-log "info" "Package $user/$repo uninstalled successfully."
    else
        .zgr-log "warn" "Package $user/$repo is not installed."
    fi
}

zgr-clean () {
    builtin emulate -LR zsh -o extendedglob

    .zgr-log "info" "Cleaning up unused packages and symlinks."
    .zgr-log "debug" "_ZGR_INSTALLED: $_ZGR_INSTALLED"

    # Remove all directories in $ZGR_PKG_DIR that are not in _ZGR_INSTALLED
    local pkg
    for pkg in $ZGR_PKG_DIR/*; do
        .zgr-log "debug" "Checking package: $pkg"
        if [[ -d $pkg ]] && (( ! $_ZGR_INSTALLED[(I)$pkg:t] )); then
            .zgr-log "info" "Removing unused package: $pkg"
            rm -rf "$pkg"
        fi
    done

    # Remove all broken symlinks in $ZGR_BIN_DIR and $ZGR_COMP_DIR
    (rm -f $ZGR_BIN_DIR/*(-@) $ZGR_COMP_DIR/*(-@)) 2> /dev/null

    .zgr-log "info" "Cleanup completed."
}

#############
## HELPERS ##
#############

.zgr-log() {
    builtin emulate -LR zsh -o extendedglob

    local level="$1"
    local msg="$2"

    # funcstack[1] is `.zgr-log`, funcstack[2] is the caller
    local caller=""
    if [[ ${#funcstack[@]} -ge 2 ]]; then
        caller=" [${funcstack[2]}]"
    fi

    # TODO: should log to stderr, but use -u2 will blow up the output
    if [[ $level == "debug" && $ZGR_DEBUG -eq 1 ]]; then
        builtin print -u2 -r -P -- "%F{cyan}[DEBUG]$caller%f $msg"
    elif [[ $level == "info" ]]; then
        builtin print -u2 -r -P -- "%F{green}[INFO]%f $msg"
    elif [[ $level == "warn" ]]; then
        builtin print -u2 -r -P -- "%F{yellow}[WARN]%f $msg"
    elif [[ $level == "error" ]]; then
        builtin print -u2 -r -P -- "%F{red}[ERROR]%f $msg"
    else
        return
    fi
}

.zgr-download-file() {
    builtin emulate -LR zsh -o extendedglob

    local url="$1"
    local dest="$2"

    # if GITHUB_TOKEN is set and url contains "api", use it for authentication
    local optC=() optW=()
    if [[ -n $GITHUB_TOKEN && $url == *"api.github.com"* ]]; then
        optC=(-H "Authorization: Bearer $GITHUB_TOKEN")
        optW=(--header="Authorization: Bearer $GITHUB_TOKEN")
    fi

    if command -v curl &> /dev/null; then
        curl -fsSL "${optC[@]}" -o "$dest" "$url" || {
            .zgr-log "error" "Failed to download $url using curl."
            return 1
        }
    elif command -v wget &> /dev/null; then
        wget -q "${optW[@]}" -O "$dest" "$url" || {
            .zgr-log "error" "Failed to download $url using wget."
            return 1
        }
    else
        .zgr-log "error" "No download tool available (curl or wget)."
        return 1
    fi

    return 0
}

.zgr-extract() {
    builtin emulate -LR zsh -o extendedglob

    local file="$1"
    local dest="$2"  # directory to extract to

    case "$file" in
        *.zip)
            unzip "$file" -d "$dest"
            rm -f "$file"
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "$file" -C "$dest"
            rm -f "$file"
            ;;
        *.tar.bz2)
            tar -xjf "$file" -C "$dest"
            rm -f "$file"
            ;;
        *.gz)
            mv "$file" "$dest" && gzip -d "$dest/${file:t}"
            ;;
        (#i)*.appimage)
            mv "$file" "$dest"
            ;;
        *.*)
            .zgr-log "error" "Unsupported archive format: $file"
            return 1
            ;;
        *)
            # No extraction needed for non-archive files
            mv "$file" "$dest"
            ;;
    esac

    return 0
}

.zgr-get-arch () {
    # copied from zinit
    builtin emulate -LR zsh -o extendedglob
    setopt noshortloops nowarncreateglobal rcquotes

    local _clib="gnu"
    local _cpu="$(uname -m)"
    local _os="$(uname -s)"
    local _sys=""

    case "$_os" in
        (Darwin)
            _sys='(apple|darwin|apple-darwin|dmg|mac((-|)os|)|os(-|64|)x)'
            arch -x86_64 /usr/bin/true 2> /dev/null
            if [[ $? -eq 0 ]] && [[ $_cpu != "arm64" ]]; then
                _os=$_sys*~*((aarch|arm)64)
            fi
            ;;
        (Linux)
            _sys='(musl|gnu)*~^*(unknown|)linux*'
            ;;
        (MINGW* | MSYS* | CYGWIN* | Windows_NT)
            _sys='pc-windows-gnu'
            ;;
        (*)
            .zgr-log "error" "Unsupported OS: $_os"
            return 1
            ;;
    esac

    case "$_cpu" in
        (aarch64 | arm64)
            _cpu='(arm|aarch)64'
            ;;
        (amd64 | i386 | i486 | i686 | i786 | x64 | x86 | x86-64 | x86_64)
            _cpu='(amd64|x86_64|x64)'
            ;;
        (armv6l)
            _os=${_os}eabihf
            ;;
        (armv7l | armv8l)
            _os=${_os}eabihf
            ;;
        (*)
            .zgr-log "error" "Unsupported CPU: $_cpu"
            return 1
            ;;
    esac

    # return glob patterns in semicolon separated list
    echo "${_sys};${_cpu};${_os}"
}

.zgr-get-gh-r-asset-list-api() {
    builtin emulate -LR zsh -o extendedglob

    local user="$1"
    local repo="$2"
    local version="$3"

    local url assets

    # get the latest version if not provided
    if [[ -z $version || $version == "latest" ]]; then
        url="https://api.github.com/repos/$user/$repo/releases/latest"
    else
        url="https://api.github.com/repos/$user/$repo/releases/tags/$version"
    fi

    assets=(
        ${(@f)"$(
            .zgr-download-file $url /dev/stdout | \
            .zgr-parse-json | \
            grep 'browser_download_url' | \
            sed -E 's/.*"(https:[^"]+)"/\1/'
        )"}
    )
    .zgr-log "debug" "assets: $assets"
    (( ${#assets} == 0 )) && {
        .zgr-log "error" "Failed to get the assets for $user/$repo."
        return 1
    }

    # return semicolon separated list of assets, which are urls
    # to solve: `arr=(${(@s.;.)str})`
    echo "${(j.;.)assets}"
}

# get assets from github release page using crawler approach
.zgr-get-gh-r-asset-list-web() {
    builtin emulate -LR zsh -o extendedglob

    local user="$1"
    local repo="$2"
    local version="$3"

    local url assests

    # get the latest version if not provided
    if [[ -z $version || $version == "latest" ]]; then
        url="https://github.com/$user/$repo/releases/latest"
        version=$(
            { .zgr-download-file $url /dev/stdout || return 1 } 2>/dev/null | \
            grep -m1 -o 'href=./'$user'/'$repo'/releases/tag/[^"]\+'
        )
        version=${version##*/}
    fi
    .zgr-log "debug" "version: $version"
    [[ -z $version ]] && {
        .zgr-log "error" "Failed to get the latest version for $user/$repo."
        return 1
    }

    url="https://github.com/$user/$repo/releases/expanded_assets/$version"
    assets=(
        ${(@f)"$(
            .zgr-download-file $url /dev/stdout | \
            grep -i -o 'href=./'$user'/'$repo'/releases/download/[^"]\+' | \
            sed -E 's/^href=./https:\/\/github.com/'
        )"}
    )
    .zgr-log "debug" "assets: $assets"
    (( ${#assets} == 0 )) && {
        .zgr-log "error" "Failed to get the assets for $user/$repo."
        return 1
    }

    # return semicolon separated list of assets, which are urls
    # to solve: `arr=(${(@s.;.)str})`
    echo "${(j.;.)assets}"
}

.zgr-get-gh-r-asset() {
    builtin emulate -LR zsh -o extendedglob

    local user="$1"
    local repo="$2"
    local version="$3"
    local bpicks="$4"

    local assets
    if [[ $ZGR_USE_GITHUB_API -eq 1 ]]; then
        assets=(${(@s.;.)$(.zgr-get-gh-r-asset-list-api "$user" "$repo" "$version")})
    else
        assets=(${(@s.;.)$(.zgr-get-gh-r-asset-list-web "$user" "$repo" "$version")})
    fi

    # copied from zinit, not sure how it works
    local parts=(${(@s.;.)$(.zgr-get-arch)})
    bpicks=(${(@s.;.)bpicks})
    [[ -z $bpicks ]] && bpicks=("")
    local bpick list filtered
    local reply=()
    for bpick in "${bpicks[@]}"; do
        .zgr-log "debug" "bpick: $bpick"
        list=($assets)
        if [[ -n $bpick ]]; then
            list=( ${(M)list[@]:#(#i)*/$~bpick} )
            if (( !$#list )); then
                .zgr-log "error" "Found no release assets. To fix, modify the pick glob pattern: $bpick"
            fi
        else
            local junk='*((s(ha256|ig|um)|386|asc|md5|txt|vsix)*|(apk|b3|deb|json|pkg|rpm|sh|zst)(#e))';
            filtered=( ${(m@)list:#(#i)${~junk}} ) && (( $#filtered > 0 )) && list=( ${filtered[@]} )
            .zgr-log "debug" "junk filtered: $filtered"
        fi

        local -a array=( $(print -rm "*(${MACHTYPE}|${VENDOR}|)*~^*(${parts[1]}|${(L)$(uname)})*" $list[@]) )
        (( ${#array} > 0 )) && list=( ${array[@]} )
        .zgr-log "debug" "MACHTYPE array: $array"

        for part in "${parts[@]}"; do
            if (( $#list > 1 )); then
                filtered=( ${(M)list[@]:#(#i)*${~part}*} ) && (( $#filtered > 0 )) && list=( ${filtered[@]} )
                .zgr-log "debug" "part: $part; part filtered: $filtered"
            else
                break
            fi
        done

        if (( $#list > 1 )); then
            filtered=( ${list[@]:#(#i)*.(sha[[:digit:]]#|asc)} ) && (( $#filtered > 0 )) && list=( ${filtered[@]} )
            .zgr-log "debug" "sha filtered: $filtered"
        fi

        if (( !$#list )); then
            .zgr-log "error" "No GitHub release assets found for $version"
            return 1
        fi
        reply+=( "${list[1]}" )
    done

    .zgr-log "debug" "reply: $reply"
    if (( ${#reply} > 1 )); then
        .zgr-log "warn" "Multiple assets found: ${reply[@]}, use first one."
    fi
    echo "${reply[1]}"
}

#####################
## SOURCE EXECUTED ##
#####################

mkdir -p "$ZGR_DIR" "$ZGR_BIN_DIR" "$ZGR_PKG_DIR" "$ZGR_COMP_DIR"

path=( $ZGR_BIN_DIR $path )
fpath=( $ZGR_COMP_DIR $fpath )

if [[ $ZGR_CONFIG == "0" || $ZGR_CONFIG == "false" ]]; then
    .zgr-log "debug" "ZGR_CONFIG is set to false, skipping configuration file loading."
    return 0
elif [[ -f "$ZGR_CONFIG" ]]; then
    . "$ZGR_CONFIG"
else
    .zgr-log "error" "Configuration file $ZGR_CONFIG not found. Please create it."
    retrun 1
fi
