#!/bin/bash

_swiftkhd() {
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    COMPREPLY=()
    opts="-c --config -V --verbose --no-hotload -h -o --observe -P --profile -k --key -t --text --install-service --uninstall-service --start-service --stop-service --restart-service --status -r --reload --version -h --help"
    if [[ $COMP_CWORD == "1" ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return
    fi
    case $prev in
        -c|--config)

            return
        ;;
        -k|--key)

            return
        ;;
        -t|--text)

            return
        ;;
    esac
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}


complete -F _swiftkhd swiftkhd
