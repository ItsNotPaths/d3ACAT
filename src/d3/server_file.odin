package d3

// network/server_file.xml, the online playlist. Each leaf <racetype> lists the
// classes it allows as a run of <vehicleclass value="..."/> lines. Every run
// gets every class the file names anywhere, plus `extra`.

import "core:strings"

server_file_all_classes :: proc(text: string, extra: []string) -> string {
	names := make([dynamic]string, context.temp_allocator)
	for line in strings.split_lines(text, context.temp_allocator) {
		if name, is_class := class_value(line); is_class && !has_name(names[:], name) {
			append(&names, name)
		}
	}
	for name in extra {
		if !has_name(names[:], name) {
			append(&names, name)
		}
	}

	b := strings.builder_make(context.temp_allocator)
	run := make([dynamic]string, context.temp_allocator)
	indent := ""
	rest := text
	for len(rest) > 0 {
		end := strings.index_byte(rest, '\n')
		line := end < 0 ? rest : rest[:end + 1]
		rest = rest[len(line):]
		if name, is_class := class_value(line); is_class {
			append(&run, name)
			indent = line[:len(line) - len(strings.trim_left_space(line))]
		} else if len(run) > 0 {
			for name in names {
				if !has_name(run[:], name) {
					strings.write_string(&b, indent)
					strings.write_string(&b, `<vehicleclass value="`)
					strings.write_string(&b, name)
					strings.write_string(&b, "\" />\r\n")
				}
			}
			clear(&run)
		}
		strings.write_string(&b, line)
	}
	return strings.to_string(b)
}

// `<vehicleclass value="name" />` alone on its line.
@(private = "file")
class_value :: proc(line: string) -> (name: string, ok: bool) {
	OPEN :: `<vehicleclass value="`
	s := strings.trim_space(line)
	if !strings.has_prefix(s, OPEN) {
		return
	}
	s = s[len(OPEN):]
	end := strings.index_byte(s, '"')
	if end < 0 {
		return
	}
	return s[:end], true
}

// The game's own file spells one class two ways (groupbrally, groupBrally).
@(private = "file")
has_name :: proc(names: []string, name: string) -> bool {
	for n in names {
		if strings.equal_fold(n, name) {
			return true
		}
	}
	return false
}
