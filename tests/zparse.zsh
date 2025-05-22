emulate -LR zsh
zmodload zsh/zutil

test_zparseopts() {
    local opt_help opt_if opt_exec opt_src opt_comp opt_bin opt_ver opt_pick opt_repo

# Options:
# --help: Show help message
# --if: Conditional execution command
# --exec: Command to execute
# --src: Source files
# --comp: Completion options
# --bin: Binary options
# --ver: Version
# --pick: Pick options

    zparseopts -D -K -- \
        -help=opt_help \
        -if:=opt_if \
        -exec+:=opt_exec \
        -comp+:=opt_comp \
        -bin+:=opt_bin \
        -ver=opt_ver \
        -pick:=opt_pick \
        -src+:=opt_src

    opt_repo="$@[1]"

    print "==== Test Case ===="
    print "opt_help: $opt_help"
    print "opt_if: $opt_if"
    print "opt_exec: $opt_exec" "${#opt_exec}"
    print "opt_src: $opt_src"
    print "opt_comp: $opt_comp"
    print "opt_bin: $opt_bin"
    print "opt_ver: $opt_ver[2]"
    print "opt_pick: $opt_pick[2]"
    print "opt_repo: $opt_repo"
    print "Left args: $*"
    print "===================="
}

# 各種情境測試
test_zparseopts \
    --if "[[]]" --if "[[111]]" \
    --pick "123" \
    --exec "echo 123" \
    user/repo