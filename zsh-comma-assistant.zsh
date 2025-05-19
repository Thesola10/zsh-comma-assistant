# Copyright (c) Karim Vergnes <me@thesola.io>
# A simple set of integrations for the comma tool from Nix, which runs any
# command by temporarily copying its Nix derivation.

# The path to the nix-index database to use
: ${COMMA_INDEX_PATH:=${XDG_CACHE_HOME:-$HOME/.cache}/nix-index}

# The default path for our commands list is next to nix-index's default db
: ${COMMA_INDEX_LIST_PATH:=$COMMA_INDEX_PATH/cmds}

# The default path for our pretty commands list (autosuggest) too
: ${COMMA_INDEX_PRETTY_LIST_PATH:=$COMMA_INDEX_PATH/prettycmds}

# Whether to enable the autosuggest feature. Default is yes.
: ${COMMA_ASSISTANT_USE_AUTOSUGGEST:=1}

#############
# HIGHLIGHT #   Syntax highlighter for zsh-syntax-highlighting.
#############

typeset -gA ZSH_HIGHLIGHT_STYLES
: ${ZSH_HIGHLIGHT_STYLES[comma:cmd]:=fg=blue}

function _zsh_highlight_highlighter_comma_predicate() {
    which -p , >/dev/null 2>&1
}

function _zsh_highlight_comma_highlighter_set_highlight() {
    setopt localoptions extendedglob
    local bufword start_
    start_=$((start + off))
    bufword=${(MS)${BUFFER[$start_,$end_]}##[[:graph:]]##}
    if [[ $style == "unknown-token" ]]
    then
        local aliasbuf aliasargs
        aliasbuf=${aliases[$bufword]}
        aliasargs=(${(z)aliasbuf})
        if grep -Fx "${aliasargs[1]}" "$COMMA_INDEX_LIST_PATH" >&/dev/null \
          || grep -Fx "$bufword" "$COMMA_INDEX_LIST_PATH" >&/dev/null
        then
            _zsh_highlight_add_highlight $start $end_ comma:cmd
        fi
    fi
}

function _zsh_highlight_highlighter_comma_paint() {
    emulate -RL zsh
    setopt localoptions extendedglob
    [[ $CONTEXT == (select|vared) ]] && return
    local -a reply
    local rep
    local start end_ style off
    local ZSH_HIGHLIGHT_TOKENS_COMMANDSEPARATOR ZSH_HIGHLIGHT_TOKENS_CONTROL_FLOW

    ZSH_HIGHLIGHT_TOKENS_COMMANDSEPARATOR=('|' '||' ';' '&' '&&' $'\n' '|&' '&!' '&|')
    ZSH_HIGHLIGHT_TOKENS_CONTROL_FLOW=($'\x7b' $'\x28' '()' 'while' 'until' 'if' 'then' 'elif' 'else' 'do' 'time' 'coproc' '!')

    # Subshell to prevent unwanted variable assignments.
    # Fixes #7
    rep=$( (_zsh_highlight_main_highlighter_highlight_list -$#PREBUFFER '' 1 "$PREBUFFER$BUFFER" >&/dev/null; echo $reply;) )
    reply=(${=rep})

    off=0
    for start end_ style in $reply
    do
        _zsh_highlight_comma_highlighter_set_highlight
        off=1
    done
}

function _zsh_autosuggest_strategy_comma() {
    emulate -L zsh
    local zcmd=(${(z)1})
    local tab=$'\t'

    which $zcmd >&/dev/null && return

    if match="$(grep -w "^$zcmd$tab" "$COMMA_INDEX_PRETTY_LIST_PATH" 2>/dev/null)"
    then
        typeset -g suggestion="$@ # ${match##*$'\t'}"
    elif grep -Fx "$zcmd" "$COMMA_INDEX_LIST_PATH" >&/dev/null
    then
        typeset -g suggestion="$@ # (from multiple sources)"
    fi
}

#############
#  HANDLER  #   Command not found handler, to try and run the command thru comma
#############

if whence -f command_not_found_handler >&/dev/null
then
    # If a command_not_found_handler already exists, rename it
    eval "_cnf_old() { $(whence -f command_not_found_handler | tail -n +2)"
fi

function command_not_found_handler() {
    which -p , >&/dev/null && \
    grep -Fx "$1" "$COMMA_INDEX_LIST_PATH" >&/dev/null && \
    { , "$@"; return }  # Execute comma command with its exit code

    if which _cnf_old >&/dev/null
    then
        _cnf_old "$@"   # Load backup notfound
    else
        printf "zsh: command not found: $1\n"
        return 127      # Pretend we're the default notfound
    fi
}

#############
# UTILITIES #   User-available utility commands
#############

#
# Quick wrapper around nix-locate to find who a command belongs to
#
function where,() {
    ((COMMA_ASSISTANT_NO_DEPS)) && {
        >&2 echo "zsh-comma-assistant requires comma and nix-index, but they were not found."
        >&2 echo "This command will not work until all dependencies are satisfied."
        return 1
    }
    bold="$(tput bold)"
    ita="$(tput sitm)"
    reset="$(tput sgr0)"
    if ! items=($(nix-locate --at-root --minimal -w "/bin/${1}" | grep -v '^(.*)$'))
    then
        >&2 echo "${1}: no match."
        return 1
    else
        for item in $items
        do
            printf "$bold%s$reset (%s):\n$ita%s$reset\n"                  \
                "$(nix --extra-experimental-features 'nix-command flakes' \
                        eval --raw nixpkgs#${item//\.out/.meta}.name)"    \
                "$item"                                                   \
                "$(nix --extra-experimental-features 'nix-command flakes' \
                        eval --raw nixpkgs#${item//\.out/.meta}.description \
                    | fmt | awk '{ print "\t" $0 }')"
        done
    fi
}

#
# Wrapper around nix-locate to retrieve man pages from Nix.
# NOTE: Nixpkgs doesn't appear to use a separate input for man pages alone,
#       so this may take up lots of unnecessary disk space.
#
function man,() {
    ((COMMA_ASSISTANT_NO_DEPS)) && {
        >&2 echo "zsh-comma-assistant requires comma and nix-index, but they were not found."
        >&2 echo "This command will not work until all dependencies are satisfied."
        return 1
    }
    if ! items=($(nix-locate --at-root --minimal -r "/share/man/man[1-9]/${1}.[1-9].gz" | grep -v '^(.*)$'))
    then
        >&2 echo "No man page on nix for '$1'."
        return 1
    else
        if [[ $#items > 1 ]]
        then item=$(printf '%s\n' "${items[@]}" | fzy)
        else item=${items[1]}
        fi
        nix --extra-experimental-features 'nix-command flakes' \
            shell "nixpkgs#$item" -c man "$@"
    fi
}

#
# Download an up-to-date prebuilt nix-index database from GitHub.
# We also build a cached index of /bin commands since nix-locate is way too
# slow for syntax highlighting
#
function refresh-index() {
    ((!auto)) && ((COMMA_ASSISTANT_NO_DEPS)) && {
        >&2 echo "zsh-comma-assistant requires comma and nix-index, but they were not found."
        >&2 echo "This command will not work until all dependencies are satisfied."
        return 1
    }

    if ! ( ((auto)) && [[ -f "$COMMA_INDEX_PATH/files" ]] )
    then
        local filename="index-$(uname -m)-$(uname | tr A-Z a-z)"
        mkdir -p $COMMA_INDEX_PATH
        wget -q --progress=bar -N https://github.com/nix-community/nix-index-database/releases/latest/download/$filename -O "$COMMA_INDEX_PATH/files"
        echo "Downloaded latest nix-index cache."
    fi

    # Building our commands cache
    if ! find "$COMMA_INDEX_LIST_PATH" -newer "$COMMA_INDEX_PATH/files" \
        | grep ".*" >&/dev/null
    then
        nix-locate --db $COMMA_INDEX_PATH --at-root /bin/ \
            | cut -d/ -f6 | sort -u \
            | grep -v "^\\..*\\-wrapped\$" \
            > $COMMA_INDEX_LIST_PATH
        echo "Updated nix commands cache."
    fi

    # Building our pretty cache if zsh-autosuggestions is installed
    if ((COMMA_ASSISTANT_USE_AUTOSUGGEST))
    then
        if ! find "$COMMA_INDEX_PRETTY_LIST_PATH" -newer "$COMMA_INDEX_PATH/files" \
            | grep ".*" >&/dev/null
        then
            0="/$(whence -v refresh-index | cut -d/ -f 2-)"
            nix-locate --db $COMMA_INDEX_PATH --at-root /bin/ \
                | python3 ${0:A:h}/nix-index-pretty.py \
                > $COMMA_INDEX_PRETTY_LIST_PATH
            echo "Updated pretty nix commands cache."
        fi
    fi
}

if which -p nix-locate , >/dev/null 2>&1
then
    auto=1 refresh-index
else
    export COMMA_ASSISTANT_NO_DEPS=1
fi

