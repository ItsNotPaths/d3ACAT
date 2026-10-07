package tests

import "core:testing"
import "../src/d3"

@(private = "file")
stock_database :: proc(t: ^testing.T) -> (db: d3.Database, ok: bool) {
	data := game_file(t, "database/database.bin") or_return
	schema, _, _ := d3.schema_builtin(context.temp_allocator)
	db, _, ok = d3.database_load(data, schema, context.temp_allocator)
	testing.expect(t, ok, "stock database.bin does not load")
	return
}

@(private = "file")
has_pair :: proc(t: ^d3.Table, mode_field: string, mode: i32, class_field: string, class: i32) -> bool {
	for row in t.rows {
		if d3.row_int(t, row, mode_field) == mode && d3.row_int(t, row, class_field) == class {
			return true
		}
	}
	return false
}

// Every single-race discipline and every online race type takes every class.
@(test)
every_class_runs_every_mode :: proc(t: ^testing.T) {
	db, found := stock_database(t)
	if !found {
		return
	}
	_, _, ok := d3.classes_map_all(&db, context.temp_allocator)
	testing.expect(t, ok)

	pairs, _ := d3.database_table(&db, "sr_vehicle_class_discipline")
	disciplines, _ := d3.database_table(&db, "single_race_discipline")
	classes, _ := d3.database_table(&db, "single_race_vehicle_class")
	for disc in disciplines.rows {
		for class in classes.rows {
			testing.expect(t, has_pair(pairs, "sr_discipline_id", d3.row_int(disciplines, disc, "id"), "sr_vehicle_class_id", d3.row_int(classes, class, "id")))
		}
	}
	net, _ := d3.database_table(&db, "net_vehicle_class_restrictions")
	net_classes, _ := d3.database_table(&db, "net_vehicle_class")
	rally := i32(2)
	for class in net_classes.rows {
		testing.expect(t, has_pair(net, "net_race_type_id", rally, "net_vehicle_class_id", d3.row_int(net_classes, class, "id")))
	}

	again, _, _ := d3.classes_map_all(&db, context.temp_allocator)
	testing.expect_value(t, again, 0)
	data, msg, encoded := d3.database_encode(db, context.temp_allocator)
	testing.expectf(t, encoded, "encode: %s", msg)
	schema, _, _ := d3.schema_builtin(context.temp_allocator)
	_, _, reloaded := d3.database_load(data, schema, context.temp_allocator)
	testing.expect(t, reloaded, "the mapped database does not load back")
}

@(test)
class_add_takes_a_class_the_database_has :: proc(t: ^testing.T) {
	db, found := stock_database(t)
	if !found {
		return
	}
	net, _ := d3.database_table(&db, "net_vehicle_class")
	before := len(net.rows)
	name, _, ok := d3.class_add(&db, "groupb_rally", context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, name, "groupbrally")
	testing.expect_value(t, len(net.rows), before)

	_, _, unknown := d3.class_add(&db, "no_such_class", context.temp_allocator)
	testing.expect(t, !unknown, "a class the database does not have was accepted")
}
