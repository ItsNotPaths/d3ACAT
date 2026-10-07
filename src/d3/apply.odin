package d3

// `d3acat <game>`, start to end. Every edit starts from the live files and
// only adds what is missing, so a second run changes nothing. Nothing is
// written until every file is ready. The first write of a file keeps it as
// `<file>.orig`, which is what `restore` puts back.

import "core:bytes"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:path/filepath"
import "../nefs"

DATABASE :: "database/database.bin"
ARCHIVE :: "win_000.nfs"

@(private = "file")
Write :: struct {
	path: string,
	data: []u8,
}

// `classes` are vehicle_class file_strings to add to every mode.
apply :: proc(game: string, classes: []string) -> (msg: string, ok: bool) {
	if !os.exists(join(game, GAME_EXES[0])) {
		return fmt.tprintf("no %s in %s", GAME_EXES[0], game), false
	}
	writes := make([dynamic]Write, context.temp_allocator)

	for name in GAME_EXES {
		path := join(game, name)
		if !os.exists(path) {
			continue
		}
		data := read_file(path, &msg) or_return
		out, rekey_msg, rekeyed := exe_rekey(data)
		if !rekeyed {
			return fmt.tprintf("%s: %s", name, rekey_msg), false
		}
		if out != nil {
			append(&writes, Write{path, out})
			fmt.printfln("%s: key swapped", name)
		}
	}

	db_path := join(game, DATABASE)
	db_data := read_file(db_path, &msg) or_return
	schema, schema_msg, schema_ok := schema_builtin(context.temp_allocator)
	if !schema_ok {
		return schema_msg, false
	}
	db, load_msg, loaded := database_load(db_data, schema, context.temp_allocator)
	if !loaded {
		return fmt.tprintf("%s: %s", DATABASE, load_msg), false
	}
	if rt_msg, rt_ok := database_roundtrip_ok(db_data, db); !rt_ok {
		return fmt.tprintf("%s does not match the schema, not touching it: %s", DATABASE, rt_msg), false
	}
	server_names := make([dynamic]string, context.temp_allocator)
	for class in classes {
		server_name, class_msg, added := class_add(&db, class, context.temp_allocator)
		if !added {
			return class_msg, false
		}
		append(&server_names, server_name)
	}
	pairs, map_msg, mapped := classes_map_all(&db, context.temp_allocator)
	if !mapped {
		return map_msg, false
	}
	new_db, encode_msg, encoded := database_encode(db, context.temp_allocator)
	if !encoded {
		return encode_msg, false
	}
	if !bytes.equal(new_db, db_data) {
		append(&writes, Write{db_path, new_db})
		fmt.printfln("%s: %d class/mode rows added", DATABASE, pairs)
	}

	archive_path := join(game, ARCHIVE)
	raw := read_file(archive_path, &msg) or_return
	a, open_msg, opened := nefs.open(raw)
	if !opened {
		return fmt.tprintf("%s: %s", ARCHIVE, open_msg), false
	}
	defer nefs.close(&a)
	text, has_text := nefs.read(&a, "server_file.xml", context.temp_allocator)
	config, has_config := nefs.read(&a, "csconfig.xml", context.temp_allocator)
	csdata, has_csdata := nefs.read(&a, "csdata.xml", context.temp_allocator)
	if !has_text || !has_config || !has_csdata {
		return fmt.tprintf("%s has no server_file.xml, csconfig.xml or csdata.xml", ARCHIVE), false
	}
	stock_config := bytes.clone(config, context.temp_allocator)
	stock_csdata := bytes.clone(csdata, context.temp_allocator)
	new_text := transmute([]u8)server_file_all_classes(string(text), server_names[:])
	if _, blanked := csconfig_blank(config); !blanked {
		return "csconfig.xml has no <csmanagerinfo> list", false
	}
	if _, blanked := csdata_blank(csdata); !blanked {
		return "csdata.xml is not the BinXML layout we know", false
	}

	changed := !bytes.equal(text, new_text) || !bytes.equal(config, stock_config) || !bytes.equal(csdata, stock_csdata)
	if a.signed_by != .Ours || changed {
		replace := []nefs.File{{"server_file.xml", new_text}, {"csconfig.xml", config}, {"csdata.xml", csdata}}
		rebuilt, rebuild_msg, built := nefs.rebuild(&a, replace, context.temp_allocator)
		if !built {
			return fmt.tprintf("%s: %s", ARCHIVE, rebuild_msg), false
		}
		check, _, reopened := nefs.open(rebuilt)
		held := reopened && check.signed_by == .Ours && nefs.checks_hold(&check)
		nefs.close(&check)
		if !held {
			return fmt.tprintf("%s: the rebuilt archive fails its own checks, nothing written", ARCHIVE), false
		}
		append(&writes, Write{archive_path, rebuilt})
		fmt.printfln("%s: checksums blanked, server_file.xml %d -> %d bytes, re-signed", ARCHIVE, len(text), len(new_text))
	}

	for w in writes {
		backup_once(w.path, &msg) or_return
		atomic_write(w.path, w.data, &msg) or_return
	}
	if len(writes) == 0 {
		fmt.println("already done, nothing changed")
	}
	report(game)
	return "", true
}

// Put every `.orig` back. The `.orig` stays: it is still the stock file.
restore :: proc(game: string) -> (msg: string, ok: bool) {
	restored := 0
	for name in ([]string{GAME_EXES[0], GAME_EXES[1], DATABASE, ARCHIVE}) {
		path := join(game, name)
		saved := fmt.tprintf("%s.orig", path)
		if !os.exists(saved) {
			continue
		}
		data := read_file(saved, &msg) or_return
		atomic_write(path, data, &msg) or_return
		fmt.printfln("%s: restored", name)
		restored += 1
	}
	if restored == 0 {
		return fmt.tprintf("no .orig files in %s", game), false
	}
	report(game)
	return "", true
}

// CRC32s to compare with a friend's install: online needs them equal.
@(private = "file")
report :: proc(game: string) {
	for name in ([]string{GAME_EXES[0], GAME_EXES[1], DATABASE, ARCHIVE}) {
		if data, err := os.read_entire_file(join(game, name), context.temp_allocator); err == nil {
			fmt.printfln("  crc32 %s: %08X", name, hash.crc32(data))
		}
	}
}

// Helpers below fail by writing `msg`, so a caller's `or_return` carries it.

@(private = "file")
join :: proc(dir, name: string) -> string {
	path, _ := filepath.join({dir, name}, context.temp_allocator)
	return path
}

@(private = "file")
read_file :: proc(path: string, msg: ^string) -> (data: []u8, ok: bool) {
	err: os.Error
	data, err = os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		msg^ = fmt.tprintf("could not read %s: %v", path, err)
		return
	}
	return data, true
}

@(private = "file")
backup_once :: proc(path: string, msg: ^string) -> bool {
	saved := fmt.tprintf("%s.orig", path)
	if os.exists(saved) {
		return true
	}
	if err := os.copy_file(saved, path); err != nil {
		msg^ = fmt.tprintf("could not back up %s: %v", path, err)
		return false
	}
	return true
}

// A new file renamed over the old one, so a failed write leaves the old intact.
@(private = "file")
atomic_write :: proc(path: string, data: []u8, msg: ^string) -> bool {
	temp := fmt.tprintf("%s.d3acat-new", path)
	if err := os.write_entire_file(temp, data); err != nil {
		msg^ = fmt.tprintf("could not write %s: %v", temp, err)
		return false
	}
	if err := os.rename(temp, path); err != nil {
		_ = os.remove(temp)
		msg^ = fmt.tprintf("could not replace %s: %v", path, err)
		return false
	}
	return true
}
