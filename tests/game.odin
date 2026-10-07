package tests

import "core:fmt"
import "core:log"
import "core:os"
import "core:testing"

// The install the game-backed tests read; DIRT3_DIR overrides. They skip without one.
DEFAULT_GAME :: "/run/media/paths/SSS-Games/SteamLibrary/steamapps/common/DiRT 3 Complete Edition"

game_dir :: proc() -> string {
	dir := os.get_env("DIRT3_DIR", context.temp_allocator)
	return dir != "" ? dir : DEFAULT_GAME
}

// The stock copy of a game file: its `.orig` once one exists.
game_file :: proc(t: ^testing.T, name: string) -> (data: []u8, ok: bool) {
	path := fmt.tprintf("%s/%s.orig", game_dir(), name)
	if !os.exists(path) {
		path = fmt.tprintf("%s/%s", game_dir(), name)
	}
	err: os.Error
	data, err = os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		log.infof("skipped: no %s", path)
		return
	}
	return data, true
}
