package tests

import "core:bytes"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "../src/d3"
import "../src/nefs"

// The exe only has to hold the key; the rest of it is never read.
@(private = "file")
fake_exe :: proc(key: [128]u8) -> []u8 {
	key := key
	out := make([]u8, 4096, context.temp_allocator)
	copy(out[1000:], key[:])
	return out
}

@(private = "file")
scratch_game :: proc(t: ^testing.T) -> (root: string, ok: bool) {
	archive := game_file(t, "win_000.nfs") or_return
	database := game_file(t, "database/database.bin") or_return
	root, _ = os.make_directory_temp("", "d3acat-*", context.temp_allocator)
	_ = os.make_directory(fmt.tprintf("%s/database", root))
	_ = os.write_entire_file(fmt.tprintf("%s/win_000.nfs", root), archive)
	_ = os.write_entire_file(fmt.tprintf("%s/database/database.bin", root), database)
	_ = os.write_entire_file(fmt.tprintf("%s/dirt3_game.exe", root), fake_exe(nefs.STOCK_N))
	return root, true
}

@(private = "file")
read :: proc(root, name: string) -> []u8 {
	data, _ := os.read_entire_file(fmt.tprintf("%s/%s", root, name), context.temp_allocator)
	return data
}

// The game loads what we write: our key in the exe, an archive signed with it
// whose checks hold, and checksum files of their stock length with nothing listed.
@(test)
apply_writes_what_the_game_checks :: proc(t: ^testing.T) {
	root, found := scratch_game(t)
	if !found {
		return
	}
	defer os.remove_all(root)
	stock := read(root, "win_000.nfs")

	msg, ok := d3.apply(root, nil)
	testing.expectf(t, ok, "apply: %s", msg)
	ours := nefs.OUR_N
	testing.expect(t, bytes.contains(read(root, "dirt3_game.exe"), ours[:]), "exe key not swapped")

	a, open_msg, opened := nefs.open(read(root, "win_000.nfs"))
	defer nefs.close(&a)
	testing.expectf(t, opened, "open: %s", open_msg)
	testing.expect_value(t, a.signed_by, nefs.Signer.Ours)
	testing.expect(t, nefs.checks_hold(&a), "header checks fail")

	s, _, _ := nefs.open(stock)
	defer nefs.close(&s)
	for name in ([]string{"csconfig.xml", "csdata.xml"}) {
		before, _ := nefs.read(&s, name, context.temp_allocator)
		after, _ := nefs.read(&a, name, context.temp_allocator)
		testing.expectf(t, len(after) == len(before), "%s changed length", name)
	}
	config, _ := nefs.read(&a, "csconfig.xml", context.temp_allocator)
	testing.expect(t, !strings.contains(string(config), "<file "), "csconfig.xml still lists files")
}

@(test)
apply_twice_changes_nothing_and_restore_undoes_it :: proc(t: ^testing.T) {
	root, found := scratch_game(t)
	if !found {
		return
	}
	defer os.remove_all(root)
	names := []string{"dirt3_game.exe", "win_000.nfs", "database/database.bin"}
	stock := make([][]u8, len(names), context.temp_allocator)
	for name, i in names {
		stock[i] = read(root, name)
	}

	_, ok := d3.apply(root, nil)
	testing.expect(t, ok)
	once := make([][]u8, len(names), context.temp_allocator)
	for name, i in names {
		once[i] = read(root, name)
	}
	_, ok = d3.apply(root, nil)
	testing.expect(t, ok)
	for name, i in names {
		testing.expectf(t, bytes.equal(read(root, name), once[i]), "second run changed %s", name)
	}

	_, ok = d3.restore(root)
	testing.expect(t, ok)
	for name, i in names {
		testing.expectf(t, bytes.equal(read(root, name), stock[i]), "%s is not stock after restore", name)
	}
}

@(test)
unknown_exe_is_refused :: proc(t: ^testing.T) {
	_, _, ok := d3.exe_rekey(make([]u8, 4096, context.temp_allocator))
	testing.expect(t, !ok, "an exe without the stock key was accepted")
}
