package d3

// The checksum manager: network/csconfig.xml lists the files it checks and
// network/csdata.xml (BinXML) holds their expected CRC32s. Blanked the way
// dirtbench blanks them (src/d3/online.odin), so no file is checked and every
// player reports the same (valid, 0). Modded files then race online.

import "core:encoding/endian"
import "core:strings"

// Spaces over everything inside <csmanagerinfo>. Returns the <file> count left.
csconfig_blank :: proc(xml: []u8) -> (files: int, ok: bool) {
	text := string(xml)
	OPEN :: "<csmanagerinfo>"
	start := strings.index(text, OPEN)
	end := strings.index(text, "</csmanagerinfo>")
	if start < 0 || end < start {
		return
	}
	start += len(OPEN)
	files = strings.count(text[start:end], "<file ")
	for &b in xml[start:end] {
		b = ' '
	}
	return files, true
}

// NUL the first byte of every string used only as a <section> value; the game
// never reads `path` either. Returns how many there are.
csdata_blank :: proc(xml: []u8) -> (sections: int, ok: bool) {
	t := bxml_tables(xml) or_return
	ids := section_only_strings(xml, t) or_return
	for i in ids {
		at := bxml_string_at(xml, t, i)
		if at >= len(xml) {
			return
		}
		xml[at] = 0
	}
	return len(ids), true
}

@(private = "file")
section_only_strings :: proc(xml: []u8, t: Bxml_Tables) -> (ids: []int, ok: bool) {
	targets := make(map[int]bool, context.temp_allocator)
	keep := make(map[int]bool, context.temp_allocator)
	for e in 0 ..< t.n_elements {
		el := t.elements + 24 * e
		name_id, value_id := u32_at(xml, el), u32_at(xml, el + 4)
		n, first := u32_at(xml, el + 8), u32_at(xml, el + 12)
		if max(name_id, value_id) >= t.n_strings || first + n > t.n_attrs {
			return
		}
		keep[name_id], keep[value_id] = true, true
		is_section := bxml_string(xml, t, name_id) == "section"
		for k in first ..< first + n {
			key_id, value := u32_at(xml, t.attrs + 8 * k), u32_at(xml, t.attrs + 8 * k + 4)
			if max(key_id, value) >= t.n_strings {
				return
			}
			keep[key_id] = true
			key := bxml_string(xml, t, key_id)
			if is_section && strings.has_prefix(key, "str") {
				targets[value] = true
			} else if key != "path" {
				keep[value] = true
			}
		}
	}
	out := make([dynamic]int, context.temp_allocator)
	for i in 0 ..< t.n_strings {
		if targets[i] && !keep[i] {
			append(&out, i)
		}
	}
	return out[:], true
}

@(private = "file")
Bxml_Tables :: struct {
	offsets, elements, attrs:       int,
	n_strings, n_elements, n_attrs: int,
}

@(private = "file")
BXML_STRINGS :: 24

@(private = "file")
bxml_tables :: proc(xml: []u8) -> (t: Bxml_Tables, ok: bool) {
	if len(xml) < BXML_STRINGS {
		return
	}
	t.offsets = BXML_STRINGS + u32_at(xml, 20) + 8
	t.n_strings = u32_at(xml, t.offsets - 4) / 4
	t.elements = t.offsets + 4 * t.n_strings + 8
	t.n_elements = u32_at(xml, t.elements - 4) / 24
	t.attrs = t.elements + 24 * t.n_elements + 8
	t.n_attrs = u32_at(xml, t.attrs - 4) / 8
	return t, t.attrs + 8 * t.n_attrs <= len(xml)
}

@(private = "file")
bxml_string_at :: proc(xml: []u8, t: Bxml_Tables, i: int) -> int {
	return BXML_STRINGS + u32_at(xml, t.offsets + 4 * i)
}

@(private = "file")
bxml_string :: proc(xml: []u8, t: Bxml_Tables, i: int) -> string {
	if i < 0 || i >= t.n_strings {
		return ""
	}
	at := bxml_string_at(xml, t, i)
	end := at
	for end < len(xml) && xml[end] != 0 {
		end += 1
	}
	return string(xml[min(at, end):end])
}

// 0 past the end, so a short file reads as empty tables.
@(private = "file")
u32_at :: proc(d: []u8, at: int) -> int {
	return at >= 0 && at + 4 <= len(d) ? int(endian.unchecked_get_u32le(d[at:])) : 0
}
