#########
## ENV ##
#########

ZGR_CONFIG="${ZGR_CONFIG:-$HOME/.zgr_config.zsh}"
ZGR_DIR="${ZGR_DIR:-$HOME/.zgr}"
ZGR_BIN_DIR="${ZGR_BIN_DIR:-$ZGR_DIR/bin}"
ZGR_PKG_DIR="${ZGR_PKG_DIR:-$ZGR_DIR/pkgs}"
ZGR_COMP_DIR="${ZGR_COMP_DIR:-$ZGR_DIR/completions}"
# ZGR_MAN_DIR="${ZGR_MAN_DIR:-$ZGR_DIR/man}"
ZGR_USE_GITHUB_API="${ZGR_USE_GITHUB_API:-1}"
ZGR_DEBUG="${ZGR_DEBUG:-0}"

#####################
## SOURCE EXECUTED ##
#####################

set -eo pipefail

builtin source "${0:A:h}/JSON.sh" || {
    echo "Error: JSON.sh not found."
    return 1
}

# mkdir -p "$ZGR_DIR" "$ZGR_BIN_DIR" "$ZGR_PKG_DIR" "$ZGR_COMP_DIR"

# path=( $ZGR_BIN_DIR $path )
# fpath=( $ZGR_COMP_DIR $fpath )

# source "$ZGR_CONFIG" 2>/dev/null || {
#   echo "Warning: $ZGR_CONFIG not found. Please create it."
#   return 1
# }

##########
## MAIN ##
##########

zgr-install () {
    builtin emulate -LR zsh -o extendedglob
    zmodload zsh/zutil

    local opt_help opt_if opt_exec opt_src opt_comp opt_bin opt_ver opt_pick opt_repo

    zparseopts -D -K -- \
        -help=opt_help \
        -if+:=opt_if \
        -exec+:=opt_exec \
        -src+:=opt_src \
        -comp+:=opt_comp \
        -bin+:=opt_bin \
        -ver=opt_ver \
        --pick:=opt_pick

    opt_repo="$@[1]"

    local user="${opt_repo%%/*}"
    local repo="${opt_repo#*/}"
    local pkg_dir="$ZGR_PKG_DIR/$user---$repo"

    # Check if the package is already installed
    if [[ -d "$pkg_dir" ]]; then
        .zgr-log "debug" "Package $user/$repo is already installed in $pkg_dir."
        return 0
    else
        .zgr-log "info" "Installing package $user/$repo."
        mkdir -p "$pkg_dir" || {
            .zgr-log "error" "Failed to create directory $pkg_dir."
            return 1
        }
    fi

    # Get the asset URL
    local asset_url
    asset_url=$(
        .zgr-get-gh-r-asset "$user" "$repo" "$opt_ver" "$opt_pick" || {
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

    # Extract the asset
    .zgr-extract "$asset_path" "$pkg_dir" || {
        .zgr-log "error" "Failed to extract asset $asset_file."
        return 1
    }

    .zgr-log "info" "Package $user/$repo installed successfully."
}

zgr-uninstall () {}

zgr-update () {}

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


################
## References ##
################

# # FUNCTION: +zi-log [[[
# # Logging function
# +zi-log() {
#     builtin emulate -LR zsh -o extendedglob ${=${options[xtrace]:#off}:+-o xtrace}
#     local opt msg
#     [[ $1 = -* ]] && { local opt=$1; shift; }

#     ZINIT[__last-formatter-code]=
#     msg=${${(j: :)${@:#--}}//\%/%%}

#     if [[ -z $ZINIT[DEBUG] ]] && [[ "$msg" = (#s){dbg}* ]]; then
#         return
#     fi

#     [[ -z $msg ]] && return

#     # Reset color attributes at the end of the message
#     msg=$msg$ZINIT[col-rst]
#     # Output the processed message:
#     builtin print -Pr ${opt:#--} -- $msg

#     # Needed to correctly end a message with {nl}.
#     if [[ -n ${opt:#*n*} || -z $opt ]]; then
#         print -n $'\015'
#     fi
# } # ]]]

# # FUNCTION: .zinit-download-file-stdout [[[
# # Downloads file to stdout. Supports following backend commands:
# # curl, wget, lftp, lynx. Used by snippet loading.
# .zinit-download-file-stdout() {
#     local url="$1" restart="$2" progress="${(M)3:#1}"

#     builtin emulate -LR zsh ${=${options[xtrace]:#off}:+-o xtrace}
#     setopt localtraps extendedglob

#     # Return file directly for file:// urls, wget doesn't support this schema
#     if [[ "$url" =~ ^file:// ]] {
#         local filepath=${url##file://}
#         <"$filepath"
#         return "$?"
#     }

#     if (( restart )) {
#         (( ${path[(I)/usr/local/bin]} )) || \
#             {
#                 path+=( "/usr/local/bin" );
#                 trap "path[-1]=()" EXIT
#             }

#         if (( ${+commands[curl]} )); then
#             if [[ -n $progress ]]; then
#                 command curl --progress-bar -fSL "$url" 2> >(.zinit-single-line >&2) || return 1
#             else
#                 command curl -fsSL "$url" || return 1
#             fi
#         elif (( ${+commands[wget]} )); then
#             command wget ${${progress:--q}:#1} "$url" -O - || return 1
#         elif (( ${+commands[lftp]} )); then
#             command lftp -c "cat $url" || return 1
#         elif (( ${+commands[lynx]} )); then
#             command lynx -source "$url" || return 1
#         else
#             +zi-log "{u-warn}ERROR{b-warn}:{rst}No download tool detected" \
#                 "(one of: {cmd}curl{rst}, {cmd}wget{rst}, {cmd}lftp{rst}," \
#                 "{cmd}lynx{rst})."
#             return 2
#         fi
#     } else {
#         if type curl 2>/dev/null 1>&2; then
#             if [[ -n $progress ]]; then
#                 command curl --progress-bar -fSL "$url" 2> >(.zinit-single-line >&2) || return 1
#             else
#                 command curl -fsSL "$url" || return 1
#             fi
#         elif type wget 2>/dev/null 1>&2; then
#             command wget ${${progress:--q}:#1} "$url" -O - || return 1
#         elif type lftp 2>/dev/null 1>&2; then
#             command lftp -c "cat $url" || return 1
#         else
#             .zinit-download-file-stdout "$url" "1" "$progress"
#             return $?
#         fi
#     }

#     return 0
# } # ]]]

# # FUNCTION: .zi::get-architecture [[[
# .zi::get-architecture () {
#   emulate -L zsh
#   setopt extendedglob noshortloops nowarncreateglobal rcquotes
#   local _clib="gnu" _cpu="$(uname -m)" _os="$(uname -s)" _sys=""
#   case "$_os" in
#     (Darwin)
#       _sys='(apple|darwin|apple-darwin|dmg|mac((-|)os|)|os(-|64|)x)'
#       arch -x86_64 /usr/bin/true 2> /dev/null
#       if [[ $? -eq 0 ]] && [[ $_cpu != "arm64" ]]; then
#         _os=$_sys*~*((aarch|arm)64)
#       fi
#       ;;
#     (Linux)
#       _sys='(musl|gnu)*~^*(unknown|)linux*'
#       ;;
#     (MINGW* | MSYS* | CYGWIN* | Windows_NT)
#       _sys='pc-windows-gnu'
#       ;;
#     (*)
#       +zi-log "{e} {b}gh-r{rst}Unsupported OS: {obj}$_os{rst}"
#       ;;
#   esac
#   case "$_cpu" in
#     (aarch64 | arm64)
#       _cpu='(arm|aarch)64'
#       ;;
#     (amd64 | i386 | i486 | i686| i786 | x64 | x86 | x86-64 | x86_64)
#       _cpu='(amd64|x86_64|x64)'
#       ;;
#     (armv6l)
#       _os=${_os}eabihf
#       ;;
#     (armv7l | armv8l)
#       _os=${_os}eabihf
#       ;;
#     (*)
#       +zi-log "{e} {b}gh-r{rst}Unsupported CPU: {obj}$_cpu{rst}"
#       ;;
#   esac
#   echo "${_sys};${_cpu};${_os}"
# } # ]]]

# # FUNCTION: .zinit-get-latest-gh-r-url-part [[[
# # Gets version string of latest release of given Github
# # package. Connects to Github releases page.
# .zinit-get-latest-gh-r-url-part () {
#   builtin emulate -LR zsh ${=${options[xtrace]:#off}:+-o xtrace}
#   setopt extendedglob nowarncreateglobal typesetsilent noshortloops
#   REPLY=
#   local plugin="$2" urlpart="$3" user="$1"
#   local -a bpicks filtered init_list list parts
#   parts=(${(@s:;:)$(.zi::get-architecture)})
#   if [[ -z $urlpart ]]; then
#     local tag_version=${ICE[ver]}
#     if [[ -z $tag_version ]]; then
#       local releases_url=https://github.com/$user/$plugin/releases/latest
#       tag_version="$( { .zinit-download-file-stdout $releases_url || .zinit-download-file-stdout $releases_url 1; } 2>/dev/null | command grep -m1 -o 'href=./'$user'/'$plugin'/releases/tag/[^"]\+' )"
#       tag_version=${tag_version##*/}
#     fi
#     local url=https://github.com/$user/$plugin/releases/expanded_assets/$tag_version
#   else
#     local url=https://$urlpart
#   fi
#   init_list=( ${(@f)"$( { .zinit-download-file-stdout $url || .zinit-download-file-stdout $url 1; } 2>/dev/null | command grep -i -o 'href=./'$user'/'$plugin'/releases/download/[^"]\+')"} )
#   init_list=(${(L)init_list[@]#href=?})
#   bpicks=(${(s.;.)ICE[bpick]})
#   [[ -z $bpicks ]] && bpicks=("")
#   local bpick bpick_error=""
#   reply=()
#   for bpick in "${bpicks[@]}"; do
#     list=($init_list)
#     if [[ -n $bpick ]]; then
#       list=( ${(M)list[@]:#(#i)*/$~bpick} )
#       if (( !$#list )); then
#         +zi-log "{e} {b}gh-r{rst}: {ice}bpick{rst} ice found no release assets To fix, modify the {ice}bpick{rst} glob pattern {glob}$bpick{rst}"
#       fi
#     else
#       local junk='*((s(ha256|ig|um)|386|asc|md5|txt|vsix)*|(apk|b3|deb|json|pkg|rpm|sh|zst)(#e))';
#       # print -l ${${(m@)list:#${~junk}}:t}
#       filtered=( ${(m@)list:#(#i)${~junk}} ) && (( $#filtered > 0 )) && list=( ${filtered[@]} )
#     fi

#     local -a array=( $(print -rm "*(${MACHTYPE}|${VENDOR}|)*~^*(${parts[1]}|${(L)$(uname)})*" $list[@]) )
#     (( ${#array} > 0 )) && list=( ${array[@]} )

#     for part in "${parts[@]}"; do
#       if (( $#list > 1 )); then
#         filtered=( ${(M)list[@]:#(#i)*${~part}*} ) && (( $#filtered > 0 )) && list=( ${filtered[@]} )
#       else
#         break
#       fi
#     done

#     if (( $#list > 1 )) { filtered=( ${list[@]:#(#i)*.(sha[[:digit:]]#|asc)} ) && (( $#filtered > 0 )) && list=( ${filtered[@]} ); }

#     if (( !$#list )); then
#       +zi-log "{e} {b}gh-r{rst}: No GitHub release assets found for {glob}$tag_version{rst}"
#       return 1
#     fi
#     reply+=( "${list[1]}" )
#   done
#   [[ -n $reply ]]
# } # ]]]

# # FUNCTION: ziextract [[[
# # If the file is an archive, it is extracted by this function.
# # Next stage is scanning of files with the common utility file
# # to detect executables. They are given +x mode. There are also
# # messages to the user on performed actions.
# #
# # $1 - url
# # $2 - file
# ziextract() {
#     builtin emulate -LR zsh ${=${options[xtrace]:#off}:+-o xtrace}
#     setopt extendedglob typesetsilent noshortloops # warncreateglobal

#     local -aU opt_move opt_move2 opt_norm opt_auto opt_nobkp
#     zparseopts -D -E -move=opt_move -move2=opt_move2 -norm=opt_norm \
#             -auto=opt_auto -nobkp=opt_nobkp || \
#         { +zi-log "{info}[{pre}ziextract{info}]{error} Incorrect options given to" \
#                   "\`{pre}ziextract{msg2}' (available are: {meta}--auto{msg2}," \
#                   "{meta}--move{msg2}, {meta}--move2{msg2}, {meta}--norm{msg2}," \
#                   "{meta}--nobkp{msg2}).{rst}"; return 1; }

#     local file="$1" ext="$2"
#     integer move=${${${(M)${#opt_move}:#0}:+0}:-1} \
#             move2=${${${(M)${#opt_move2}:#0}:+0}:-1} \
#             norm=${${${(M)${#opt_norm}:#0}:+0}:-1} \
#             auto=${${${(M)${#opt_auto}:#0}:+0}:-1} \
#             nobkp=${${${(M)${#opt_nobkp}:#0}:+0}:-1}

#     if (( auto )) {
#         # First try known file extensions
#         local -aU files
#         integer ret_val
#         files=( (#i)**/*.(zip|rar|7z|tgz|tbz|tbz2|tar.gz|tar.bz2|tar.7z|txz|tar.xz|gz|xz|tar|dmg|exe)~(*/*|.(_backup|git))/*(-.DN) )
#         for file ( $files ) {
#             ziextract "$file" $opt_move $opt_move2 $opt_norm $opt_nobkp ${${${#files}:#1}:+--nobkp}
#             ret_val+=$?
#         }
#         # Second, try to find the archive via `file' tool
#         if (( !${#files} )) {
#             local -aU output infiles stage2_processed archives
#             infiles=( **/*~(._zinit*|._backup|.git)(|/*)~*/*/*(-.DN) )
#             output=( ${(@f)"$(command file -- $infiles 2>&1)"} )
#             archives=( ${(M)output[@]:#(#i)(* |(#s))(zip|rar|xz|7-zip|gzip|bzip2|tar|exe|PE32) *} )
#             for file ( $archives ) {
#                 local fname=${(M)file#(${(~j:|:)infiles}): } desc=${file#(${(~j:|:)infiles}): } type
#                 fname=${fname%%??}
#                 [[ -z $fname || -n ${stage2_processed[(r)$fname]} ]] && continue
#                 type=${(L)desc/(#b)(#i)(* |(#s))(zip|rar|xz|7-zip|gzip|bzip2|tar|exe|PE32) */$match[2]}
#                 if [[ $type = (zip|rar|xz|7-zip|gzip|bzip2|tar|exe|pe32) ]] {
#                     (( !OPTS[opt_-q,--quiet] )) && \
#                         +zi-log "{info}[{pre}ziextract{info}]{msg2} detected a {meta}$type{rst} archive in the file {file}$fname{rst}."
#                     ziextract "$fname" "$type" $opt_move $opt_move2 $opt_norm --norm ${${${#archives}:#1}:+--nobkp}
#                     integer iret_val=$?
#                     ret_val+=iret_val

#                     (( iret_val )) && continue

#                     # Support nested tar.(bz2|gz|…) archives
#                     local infname=$fname
#                     [[ -f $fname.out ]] && fname=$fname.out
#                     files=( *.tar(ND) )
#                     if [[ -f $fname || -f ${fname:r} ]] {
#                         local -aU output2 archives2
#                         output2=( ${(@f)"$(command file -- "$fname"(N) "${fname:r}"(N) $files[1](N) 2>&1)"} )
#                         archives2=( ${(M)output2[@]:#(#i)(* |(#s))(zip|rar|xz|7-zip|gzip|bzip2|tar|exe|PE32) *} )
#                         local file2
#                         for file2 ( $archives2 ) {
#                             fname=${file2%:*} desc=${file2##*:}
#                             local type2=${(L)desc/(#b)(#i)(* |(#s))(zip|rar|xz|7-zip|gzip|bzip2|tar|exe|PE32) */$match[2]}
#                             if [[ $type != $type2 && \
#                                 $type2 = (zip|rar|xz|7-zip|gzip|bzip2|tar)
#                             ]] {
#                                 # TODO: if multiple archives are really in the archive,
#                                 # this might delete too soon… However, it's unusual case.
#                                 [[ $fname != $infname && $norm -eq 0 ]] && command rm -f "$infname"
#                                 (( !OPTS[opt_-q,--quiet] )) && \
#                                     +zi-log "{info}[{pre}ziextract{info}]{msg2} detected a {obj}${type2}{rst} archive in the file {file}${fname}{rst}."
#                                 ziextract "$fname" "$type2" $opt_move $opt_move2 $opt_norm ${${${#archives}:#1}:+--nobkp}
#                                 ret_val+=$?
#                                 stage2_processed+=( $fname )
#                                 if [[ $fname == *.out ]] {
#                                     [[ -f $fname ]] && command mv -f "$fname" "${fname%.out}"
#                                     stage2_processed+=( ${fname%.out} )
#                                 }
#                             }
#                         }
#                     }
#                 }
#             }
#         }
#         return $ret_val
#     }

#     if [[ -z $file ]] {
#         +zi-log "{info}[{pre}ziextract{info}]{error} argument needed (the file to extract) or the {meta}--auto{msg} option."
#         return 1
#     }
#     if [[ ! -e $file ]] {
#         +zi-log "{info}[{pre}ziextract{info}]{error} ERROR:{msg} the file \`{meta}${file}{msg}' doesn't exist.{rst}"
#         return 1
#     }
#     if (( !nobkp )) {
#         command mkdir -p ._backup
#         command rm -rf ._backup/*(DN)
#         command mv -f *~(._zinit*|._backup|.git|.svn|.hg|$file)(DN) ._backup 2>/dev/null
#     }

#     .zinit-extract-wrapper() {
#         local file="$1" fun="$2" retval
#         (( !OPTS[opt_-q,--quiet] )) && \
#             +zi-log "{info}[{pre}ziextract{info}]{rst} Unpacking the files from: \`{obj}$file{msg}'{…}{rst}"
#         $fun; retval=$?
#         if (( retval == 0 )) {
#             local -a files
#             files=( *~(._zinit*|._backup|.git|.svn|.hg|$file)(DN) )
#             (( ${#files} && !norm )) && command rm -f "$file"
#         }
#         return $retval
#     }

#     →zinit-check() { (( ${+commands[$1]} )) || \
#         +zi-log "{info}[{pre}ziextract{info}]{error} Error:{msg} No command {data}$1{msg}, it is required to unpack {file}$2{rst}."
#     }

#     case "${${ext:+.$ext}:-$file}" in
#         ((#i)*.zip)
#             →zinit-extract() { →zinit-check unzip "$file" || return 1; command unzip -qq -o "$file"; }
#             ;;
#         ((#i)*.rar)
#             →zinit-extract() { →zinit-check unrar "$file" || return 1; command unrar x "$file"; }
#             ;;
#         ((#i)*.tar.bz2|(#i)*.tbz|(#i)*.tbz2)
#             →zinit-extract() { →zinit-check bzip2 "$file" || return 1; command bzip2 -dc "$file" | command tar --no-same-owner -xf -; }
#             ;;
#         ((#i)*.tar.gz|(#i)*.tgz)
#             →zinit-extract() { →zinit-check gzip "$file" || return 1; command gzip -dc "$file" | command tar --no-same-owner -xf -; }
#             ;;
#         ((#i)*.tar.xz|(#i)*.txz)
#             →zinit-extract() { →zinit-check xz "$file" || return 1; command xz -dc "$file" | command tar --no-same-owner -xf -; }
#             ;;
#         ((#i)*.tar.7z|(#i)*.t7z)
#             →zinit-extract() { →zinit-check 7z "$file" || return 1; command 7z x -so "$file" | command tar --no-same-owner -xf -; }
#             ;;
#         ((#i)*.tar)
#             →zinit-extract() { →zinit-check tar "$file" || return 1; command tar --no-same-owner -xf "$file"; }
#             ;;
#         ((#i)*.gz|(#i)*.gzip)
#             if [[ $file != (#i)*.gz ]] {
#                 command mv $file $file.gz
#                 file=$file.gz
#                 integer zi_was_renamed=1
#             }
#             →zinit-extract() {
#                 →zinit-check gunzip "$file" || return 1
#                 .zinit-get-mtime-into "$file" 'ZINIT[tmp]'
#                 command gunzip "$file" |& command grep -E -v '.out$'
#                 integer ret=$pipestatus[1]
#                 command touch -t "$(strftime %Y%m%d%H%M.%S $ZINIT[tmp])" "$file"
#                 return ret
#             }
#             ;;
#         ((#i)*.bz2|(#i)*.bzip2)
#             # Rename file if its extension does not match "bz2". bunzip2 refuses
#             # to operate on files that are not named correctly.
#             # See https://github.com/zdharma-continuum/zinit/issues/105
#             if [[ $file != (#i)*.bz2 ]] {
#                 command mv $file $file.bz2
#                 file=$file.bz2
#             }
#             →zinit-extract() { →zinit-check bunzip2 "$file" || return 1
#                 .zinit-get-mtime-into "$file" 'ZINIT[tmp]'
#                 command bunzip2 "$file" |& command grep -E -v '.out$'
#                 integer ret=$pipestatus[1]
#                 command touch -t "$(strftime %Y%m%d%H%M.%S $ZINIT[tmp])" "$file"
#                 return ret
#             }
#             ;;
#         ((#i)*.xz)
#             if [[ $file != (#i)*.xz ]] {
#                 command mv $file $file.xz
#                 file=$file.xz
#             }
#             →zinit-extract() { →zinit-check xz "$file" || return 1
#                 .zinit-get-mtime-into "$file" 'ZINIT[tmp]'
#                 command xz -d "$file"
#                 integer ret=$?
#                 command touch -t "$(strftime %Y%m%d%H%M.%S $ZINIT[tmp])" "$file"
#                 return ret
#              }
#             ;;
#         ((#i)*.7z|(#i)*.7-zip)
#             →zinit-extract() { →zinit-check 7z "$file" || return 1; command 7z x "$file" >/dev/null;  }
#             ;;
#         ((#i)*.dmg)
#             →zinit-extract() {
#                 local prog
#                 for prog ( hdiutil cp ) { →zinit-check $prog "$file" || return 1; }

#                 integer retval
#                 local attached_vol="$( command hdiutil attach "$file" | \
#                            command tail -n1 | command cut -f 3 )"

#                 command cp -Rf ${attached_vol:-${TMPDIR:-/tmp}/acb321GEF}/*(D) .
#                 retval=$?
#                 command hdiutil detach $attached_vol

#                 if (( retval )) {
#                     +zi-log "{info}[{pre}ziextract{info}]{error} Error:{msg} problem occurred when attempted to copy the files" \
#                             "from the mounted image: \`{obj}${file}{msg}'.{rst}"
#                 }
#                 return $retval
#             }
#             ;;
#         ((#i)*.deb)
#             →zinit-extract() { →zinit-check dpkg-deb "$file" || return 1; command dpkg-deb -R "$file" .; }
#             ;;
#         ((#i)*.rpm)
#             →zinit-extract() { →zinit-check cpio "$file" || return 1; $ZINIT[BIN_DIR]/share/rpm2cpio.zsh "$file" | command cpio -imd --no-absolute-filenames; }
#             ;;
#         ((#i)*.exe|(#i)*.pe32)
#             →zinit-extract() {
#                 command chmod a+x -- ./$file
#                 ./$file /S /D="`cygpath -w $PWD`"
#             }
#             ;;
#     esac

#     if [[ $(typeset -f + →zinit-extract) == "→zinit-extract" ]] {
#         .zinit-extract-wrapper "$file" →zinit-extract || {
#             +zi-log -n "{info}[{pre}ziextract{info}]{error} Error:{msg} extraction of the archive \`{file}${file}{msg}' had problems"
#             local -a bfiles
#             bfiles=( ._backup/*(DN) )
#             if (( ${#bfiles} && !nobkp )) {
#                 +zi-log -n ", restoring the previous version of the plugin/snippet"
#                 command mv ._backup/*(DN) . 2>/dev/null
#             }
#             +zi-log ".{rst}"
#             unfunction -- →zinit-extract →zinit-check 2>/dev/null
#             return 1
#         }
#         unfunction -- →zinit-extract →zinit-check
#     } else {
#         integer warning=1
#     }
#     unfunction -- .zinit-extract-wrapper

#     local -aU execs
#     execs=( **/*~(._zinit(|/*)|.git(|/*)|.svn(|/*)|.hg(|/*)|._backup(|/*))(DN-.) )
#     if [[ ${#execs} -gt 0 && -n $execs ]] {
#         execs=( ${(@f)"$( file ${execs[@]} )"} )
#         execs=( "${(M)execs[@]:#[^(:]##:*executable*}" )
#         execs=( "${execs[@]/(#b)([^(:]##):*/${match[1]}}" )
#     }

#     builtin print -rl -- ${execs[@]} >! ${TMPDIR:-/tmp}/zinit-execs.$$.lst
#     if [[ ${#execs} -gt 0 ]] {
#         command chmod a+x "${execs[@]}"
#         if (( !OPTS[opt_-q,--quiet] )) {
#             if (( ${#execs} == 1 )); then
#                     +zi-log "{info}[{pre}ziextract{info}]{rst} Successfully extracted and assigned +x chmod to the file: {obj}${execs[1]}{rst}."
#             else
#                 local sep="$ZINIT[col-rst],$ZINIT[col-obj] "
#                 if (( ${#execs} > 7 )) {
#                     +zi-log "{info}[{pre}ziextract{info}]{rst} Successfully" \
#                         "extracted and marked executable the appropriate files" \
#                         "({obj}${(pj:$sep:)${(@)execs[1,5]:t}},…{rst}) contained" \
#                         "in \`{file}$file{rst}'. All the extracted" \
#                         "{obj}${#execs}{rst} executables are" \
#                         "available in the {msg2}INSTALLED_EXECS{rst}" \
#                         "array."
#                 } else {
#                     +zi-log "{info}[{pre}ziextract{info}]{rst} Successfully" \
#                         "extracted and marked {obj}${#execs}{rst} executable the appropriate files" \
#                         "({obj}${(pj:$sep:)${execs[@]:t}}{rst}) contained" \
#                         "in \`{file}$file{rst}'."
#                 }
#             fi
#         }
#     } elif (( warning )) {
#         +zi-log "{info}[{pre}ziextract{info}]{error} Error:{msg} didn't recognize archive type of {obj}${file}{msg} ${ext:+/ {obj2}${ext}{msg} } (no extraction has been done).{rst}"
#     }

#     if (( move | move2 )) {
#         local -a files
#         files=( *~(._zinit|.git|._backup|.tmp231ABC)(DN/) )
#         if (( ${#files} )) {
#             command mkdir -p .tmp231ABC
#             command mv -f *~(._zinit|.git|._backup|.tmp231ABC)(D) .tmp231ABC
#             if (( !move2 )) {
#                 command mv -f **/*~(*/*~*/*/*|*/*/*/*|^*/*|._zinit(|/*)|.git(|/*)|._backup(|/*))(DN) .
#             } else {
#                 command mv -f **/*~(*/*~*/*/*/*|*/*/*/*/*|^*/*|._zinit(|/*)|.git(|/*)|._backup(|/*))(DN) .
#             }

#             command mv .tmp231ABC/$file . &>/dev/null
#             command rm -rf .tmp231ABC
#         }
#         REPLY="${${execs[1]:h}:h}/${execs[1]:t}"
#     } else {
#         REPLY="${execs[1]}"
#     }
#     return 0
# } # ]]]
# # FUNCTION: .zinit-extract [[[
# .zinit-extract() {
#     builtin emulate -LR zsh ${=${options[xtrace]:#off}:+-o xtrace}
#     setopt extendedglob warncreateglobal typesetsilent
#     local tpe=$1 extract=$2 local_dir=$3
#     (
#         builtin cd -q "$local_dir" || \
#             { +zi-log "{error}ERROR:{msg2} The path of the $tpe" \
#                       "(\`{file}$local_dir{msg2}') isn't accessible.{rst}"
#                 return 1
#             }
#         local -aU files
#         files=( ${(@)${(@s: :)${extract##(\!-|-\!|\!|-)}}//(#b)(((#s)|([^\\])[\\]([\\][\\])#)|((#s)|([^\\])([\\][\\])#)) /${match[2]:+$match[3]$match[4] }${match[5]:+$match[6]${(l:${#match[7]}/2::\\:):-} }} )
#         if [[ ${#files} -eq 0 && -n ${extract##(\!-|-\!|\!|-)} ]] {
#                 +zi-log "{error}ERROR:{msg2} The files" \
#                         "(\`{file}${extract##(\!-|-\!|\!|-)}{msg2}')" \
#                         "not found, cannot extract.{rst}"
#                 return 1
#         } else {
#             (( !${#files} )) && files=( "" )
#         }
#         local file
#         for file ( "${files[@]}" ) {
#             [[ -z $extract ]] && local auto2=--auto
#             ziextract ${${(M)extract:#(\!|-)##}:+--auto} \
#                 $auto2 $file \
#                 ${${(MS)extract[1,2]##-}:+--norm} \
#                 ${${(MS)extract[1,2]##\!}:+--move} \
#                 ${${(MS)extract[1,2]##\!\!}:+--move2} \
#                 ${${${#files}:#1}:+--nobkp}
#         }
#     )
# } # ]]]
