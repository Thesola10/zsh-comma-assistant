# Copyright (c) Karim Vergnes <me@thesola.io>
# A simple set of integrations for the comma tool from Nix, which runs any
# command by temporarily copying its Nix derivation.

# The path to the nix-index database to use
: ${COMMA_INDEX_PATH:=${XDG_CACHE_HOME:-$HOME/.cache}/nix-index}

# The default path for our commands list is next to nix-index's default db
: ${COMMA_INDEX_LIST_PATH:=$COMMA_INDEX_PATH/cmds}

#
# Syntax highlighter for zsh-syntax-highlighting.
#

typeset -gA ZSH_HIGHLIGHT_STYLES
: ${ZSH_HIGHLIGHT_STYLES[comma:cmd]:=fg=blue}

function _zsh_highlight_highlighter_comma_predicate() {
    which -p , >/dev/null 2>&1
}

function _zsh_highlight_highlighter_comma_paint() {
    setopt localoptions extendedglob
    local -a args aliasbuf aliasargs
    args=(${(z)BUFFER})
    aliasbuf=${aliases[${args[1]}]}
    aliasargs=(${(z)aliasbuf})

    # If a command exists, don't overwrite the main highlighter
    ! alias "${args[1]}" &>/dev/null && whence "${args[1]}" &>/dev/null && return
    if grep -Fx "${args[1]}" "$COMMA_INDEX_LIST_PATH" &>/dev/null \
        || grep -Fx "${aliasargs[1]}" "$COMMA_INDEX_LIST_PATH" &>/dev/null
    then
        _zsh_highlight_add_highlight 0 ${#args[1]} comma:cmd
    fi
}

#
# Command not found handler, to try and run the command thru comma
#

function command_not_found_handler() {
    which -p , >/dev/null 2>&1 && \
    grep -Fx "$1" "$COMMA_INDEX_LIST_PATH" >/dev/null 2>&1 && \
    { , "$@"; return }  # Execute comma command with its exit code

    printf "zsh: command not found: $1\n"
    return 127          # Pretend we're the default notfound
}

#
# Quick wrapper around nix-locate to find who a command belongs to
#
function where,() {
    if ! nix-locate --at-root -1w "/bin/${1}" | grep -v '^(.*)$'
    then
        >&2 echo "${1}: no match."
        return 1
    fi
}

#
# Update the cached index of /bin commands (i.e. comma commands) because
# nix-locate is way too slow for a syntax highlighter.
#
if which -p nix-locate , >/dev/null 2>&1
then
    # Quick setup by downloading prebuilt index
    if ! [[ -f "$COMMA_INDEX_PATH/files" ]]
    then
        local filename="index-$(uname -m)-$(uname | tr A-Z a-z)"
        mkdir -p $COMMA_INDEX_PATH
        wget -q -N https://github.com/Mic92/nix-index-database/releases/latest/download/$filename -O "$COMMA_INDEX_PATH/files"
        echo "Downloaded latest nix-index cache."
    fi

    # Building our commands cache
    if ! find "$COMMA_INDEX_LIST_PATH" -newer "$COMMA_INDEX_PATH/files" \
        | grep ".*" >/dev/null 2>&1
    then
        nix-locate --db $COMMA_INDEX_PATH --at-root /bin/ \
            | cut -d/ -f6 | sort -u \
            | grep -v "^\\..*\\-wrapped\$" \
            > $COMMA_INDEX_LIST_PATH
        echo "Updated nix commands cache."
    fi
fi
