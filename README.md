# Vune

Vune is a terminal music player. mpv plays. Neovim is the UI. A playlist is a plain text buffer, one path per line.

## Requirements

1. mpv (tested with 0.41).
2. Neovim 0.10 or later (tested with 0.11.6).
3. Python 3.11 or later (wrapper script, standard library only).

## Install

Clone the repository, then link `bin/vune` into a directory on your `PATH`:

```shell
git clone git@github.com:crccheck/vune.git ~/src/vune
ln -s ~/src/vune/bin/vune ~/.local/bin/vune
```

`vune` follows the link to find the plugin, so keep the clone where it is.

## Usage

```shell
vune playlist.m3u [-- <mpv options>]
vune ~/Music [-- <mpv options>]
```

1. **File mode.** `playlist.m3u` is the playlist. Any extension works. The file is created if it does not exist. Put one absolute path per line.
2. **Directory mode.** Behaves like `mpv --no-video --replaygain=track ~/Music`. The buffer shows mpv's playlist, one path per line. `:w` syncs edits to mpv and writes no file. `:w list.m3u` saves the playlist as a file.
3. **`-- <mpv options>`.** Everything after `--` goes to mpv. Example: `vune ~/Music -- --shuffle --volume=40`. The options apply only when `vune` starts mpv. If mpv is already running for that playlist, they have no effect.

Quitting Neovim also quits mpv. Restarting does not resume the track position. With `--shuffle`, the order is new each start. To leave the music playing, suspend Neovim with `<C-z>` (or `:suspend`) and return with `fg`.

## Keymaps

Keymaps are not final. They are active only in the playlist buffer.

| Key | Action |
|---|---|
| `<CR>` | Play the line under the cursor |
| `<Space>` | Pause or resume |

`:VuneFollow` toggles the cursor following the current track.

## Editing the playlist

Use normal Vim commands: `dd`, `p`, `yyp`, `:g`, `:sort`. Changes reach mpv when you run `:w`. Vune compares mpv's playlist with the buffer and sends only the changes (remove, move, insert). The playing track keeps playing unless you delete its line. A duplicated line plays twice.

## Display

Text in the buffer stays plain. State shows through extmarks and the winbar:
1. Sign column: `▶` playing, `⏸` paused.
2. The current line is highlighted. Played lines are dimmed.
3. `01:23 / 04:10` at the end of the current line.
4. Winbar: `▶ Artist - Title  01:23/04:10`.

## How it works

1. The `vune` command (`bin/vune`) starts one mpv daemon per playlist. It listens on `$XDG_RUNTIME_DIR/vune/<name>-<hash>.sock`. It then runs Neovim with the plugin loaded.
2. `lua/vune/ipc.lua` talks to mpv's JSON IPC over the socket.
3. `lua/vune/init.lua` holds the player state (position, time, pause, volume, tags).
4. `lua/vune/playlist.lua` owns the buffer, the keymaps and the sync on write. `lua/vune/diff.lua` computes the minimal mpv commands.
5. `lua/vune/ui.lua` draws the indicator.

`vune` loads the plugin with `-c`, not `--cmd`, because plugin managers such as lazy.nvim reset `runtimepath` after `--cmd`. A plain `nvim` never loads the plugin.

If Neovim crashes, mpv keeps running. Running `vune` again re-attaches without restarting the track. Stop it with `pkill -x mpv`.

## Limits

1. Blank lines and `#` comment lines break the line-to-index mapping.
2. Relative paths are not resolved. Use absolute paths.
3. No library, search, ratings or autoplaylists.

## License

ISC. See [LICENSE](LICENSE).
