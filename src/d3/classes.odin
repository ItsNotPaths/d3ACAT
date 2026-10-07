package d3

// Any car on any track. Each table below says "this class may run this mode";
// a mode is the tuple of the row's other keys. Every mode a table already
// lists gets a row for every class.

import "core:fmt"
import "core:strings"

@(private = "file")
Pairing :: struct {
	table:       string,
	class_field: string,
	class_table: string,
}

@(private = "file")
PAIRINGS := [?]Pairing {
	{"sr_vehicle_class_discipline", "sr_vehicle_class_id", "single_race_vehicle_class"},
	{"tt_vehicle_class_disciplines", "vehicle_class_id", "vehicle_class"},
	{"eligible_vehicle_classes", "vehicle_class_id", "vehicle_class"},
	{"net_vehicle_class_restrictions", "net_vehicle_class_id", "net_vehicle_class"},
}

// Fill every pairing table. Returns the rows added; 0 when already done.
classes_map_all :: proc(db: ^Database, allocator := context.allocator) -> (added: int, msg: string, ok: bool) {
	for p in PAIRINGS {
		t, has_t := database_table(db, p.table)
		classes, has_c := database_table(db, p.class_table)
		if !has_t || !has_c || len(t.rows) == 0 {
			return added, fmt.tprintf("database has no %s rows", p.table), false
		}
		class_at, _ := table_field(t, p.class_field)
		modes := make([dynamic]Row, context.temp_allocator)
		for row in t.rows {
			if !has_mode(t, modes[:], row, class_at) {
				append(&modes, row)
			}
		}
		for mode in modes {
			for class in classes.rows {
				id := row_int(classes, class, "id")
				if has_pair(t, mode, class_at, id) {
					continue
				}
				row := row_clone(t, mode, allocator)
				row[class_at] = id
				row_set_int(t, row, "id", table_next_id(t))
				row_set_int(t, row, "order_index", table_max_int(t, "order_index") + 1)
				append(&t.rows, row)
				added += 1
			}
		}
	}
	return added, "", true
}

// Give the vehicle_class `name` (its file_string) a single-race class and a
// network class, if it has none. Returns its name in server_file.xml.
class_add :: proc(db: ^Database, name: string, allocator := context.allocator) -> (server_name: string, msg: string, ok: bool) {
	vehicles, _ := database_table(db, "vehicle_class")
	sr, _ := database_table(db, "single_race_vehicle_class")
	groups, _ := database_table(db, "single_race_vehicle_groups")
	net, _ := database_table(db, "net_vehicle_class")
	if vehicles == nil || sr == nil || groups == nil || net == nil {
		return "", "database is missing a vehicle class table", false
	}
	vehicle, found := find_row(vehicles, "file_string", name)
	if !found {
		return "", fmt.tprintf("no vehicle_class with file_string %q", name), false
	}
	vehicle_id := row_int(vehicles, vehicle, "id")

	if _, grouped := find_row_int(groups, "vehicle_class", vehicle_id); !grouped {
		class := row_clone(sr, sr.rows[0], allocator)
		class_id := table_next_id(sr)
		row_set_int(sr, class, "id", class_id)
		row_set_str(sr, class, "name_string_id", name, allocator)
		row_set_int(sr, class, "order_index", table_max_int(sr, "order_index") + 1)
		append(&sr.rows, class)

		group := row_clone(groups, groups.rows[0], allocator)
		row_set_int(groups, group, "id", table_next_id(groups))
		row_set_int(groups, group, "single_race_vehicle_class", class_id)
		row_set_int(groups, group, "vehicle_class", vehicle_id)
		append(&groups.rows, group)
	}
	if _, listed := find_row(net, "net_type", name); !listed {
		row := row_clone(net, net.rows[0], allocator)
		row_set_int(net, row, "id", table_next_id(net))
		row_set_str(net, row, "net_type", name, allocator)
		row_set_int(net, row, "order_index", table_max_int(net, "order_index") + 1)
		row_set_str(net, row, "session_list_string_id", fmt.tprintf("%s_session_list_veh_class", name), allocator)
		row_set_str(net, row, "type_string_id", fmt.tprintf("%s_net_veh_class", name), allocator)
		append(&net.rows, row)
	}
	server_name, _ = strings.remove_all(name, "_", context.temp_allocator)
	return server_name, "", true
}

// Same keys as `row` apart from id, order_index and the class.
@(private = "file")
same_mode :: proc(t: ^Table, a, b: Row, class_at: int) -> bool {
	for f, i in t.fields {
		if i == class_at || f.name == "id" || f.name == "order_index" {
			continue
		}
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

@(private = "file")
has_mode :: proc(t: ^Table, modes: []Row, row: Row, class_at: int) -> bool {
	for m in modes {
		if same_mode(t, m, row, class_at) {
			return true
		}
	}
	return false
}

@(private = "file")
has_pair :: proc(t: ^Table, mode: Row, class_at: int, class: i32) -> bool {
	for row in t.rows {
		if row[class_at] == Value(class) && same_mode(t, row, mode, class_at) {
			return true
		}
	}
	return false
}

@(private = "file")
find_row :: proc(t: ^Table, field, value: string) -> (Row, bool) {
	for row in t.rows {
		if row_str(t, row, field) == value {
			return row, true
		}
	}
	return nil, false
}

@(private = "file")
find_row_int :: proc(t: ^Table, field: string, value: i32) -> (Row, bool) {
	for row in t.rows {
		if row_int(t, row, field) == value {
			return row, true
		}
	}
	return nil, false
}
