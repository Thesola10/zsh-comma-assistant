# zsh-comma-assistant

Tighter integration around the [`comma`](https://github.com/nix-community/comma) utility, so you'll (almost) never get a "command not found" error ever again!

This plugin consists of two parts: a **command not found handler**, and a **syntax highlight addon**.

## Dependencies

This plugin requires [`nix-index`](https://github.com/bennofs/nix-index) to be installed and available in `PATH`, as well as for the `nix-index` database to have already been built.
It also requires [`comma`](https://github.com/nix-community/comma) (duh) to be installed in `PATH`.

### Syntax highlight

The syntax highlight addon included in this plugin requires [`zsh-syntax-highlighting`](/zsh-users/zsh-syntax-highlighting) to have been loaded _before_ this plugin.
On `zplug`, this would be represented as follows:

```zsh
zplug "zsh-users/zsh-syntax-highlighting", defer:2
...
zplug "thesola10/zsh-comma-assistant", defer:3 # (note the higher defer value)
```

If you cannot control the plugin install order, the highlight addon can still be enabled by adding it to the active highlighters:

```zsh
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main comma)
```

## Configuration

Currently, the following environment variables can be configured to control the behavior of this plugin:

- `$COMMA_INDEX_PATH` is the path to the database directory for `nix-index`. _(default: `$XDG_CACHE_HOME/nix-index`)_
- `$COMMA_INDEX_LIST_PATH` is the path where the plugin should store its auto-generated available commands list. _(default: `$COMMA_INDEX_PATH/cmds`)_
- `${ZSH_HIGHLIGHT_STYLES[comma:cmd]}` is the style to use to highlight a command available in Nix. _(default: `fg=blue`)_
