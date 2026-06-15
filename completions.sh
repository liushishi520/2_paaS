#!/bin/bash

# Bash completion for ai-cli
_ai_cli_completions() {
    local cur prev words cword
    _init_completion || return
    
    case $prev in
        ai-cli)
            COMPREPLY=($(compgen -W "llm embed rag prompt cache config help" -- "$cur"))
            return
            ;;
        llm|embed|rag|prompt|cache|config)
            COMPREPLY=($(compgen -W "--help" -- "$cur"))
            return
            ;;
    esac
    
    COMPREPLY=($(compgen -W "--help --version" -- "$cur"))
}

complete -F _ai_cli_completions ai-cli
