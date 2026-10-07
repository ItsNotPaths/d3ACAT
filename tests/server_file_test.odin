package tests

import "core:fmt"
import "core:strings"
import "core:testing"
import "../src/d3"

@(private = "file")
SERVER_FILE :: "<racetype value=\"rally\" >\r\n" +
	"  <vehicleclass value=\"wrcrally\" />\r\n" +
	"  <vehicleclass value=\"groupBrally\" />\r\n" +
	"  <track value=\"finland_rally\" />\r\n" +
	"</racetype>\r\n" +
	"<racetype value=\"gymkhana\" >\r\n" +
	"  <vehicleclass value=\"gymkhana\" />\r\n" +
	"  <vehicleclass value=\"groupbrally\" />\r\n" +
	"  <track value=\"battersea\" />\r\n" +
	"</racetype>\r\n"

@(private = "file")
racetype :: proc(text, name: string) -> string {
	start := strings.index(text, fmt.tprintf(`<racetype value=%s`, name))
	return text[start:start + strings.index(text[start:], "</racetype>")]
}

@(test)
every_racetype_lists_every_class :: proc(t: ^testing.T) {
	out := d3.server_file_all_classes(SERVER_FILE, {"sportrally"})
	for mode in ([]string{`"rally"`, `"gymkhana"`}) {
		block := racetype(out, mode)
		for class in ([]string{"wrcrally", "gymkhana", "sportrally"}) {
			testing.expectf(t, strings.count(block, fmt.tprintf(`<vehicleclass value="%s"`, class)) == 1, "%s lacks %s:\n%s", mode, class, block)
		}
		// One class, two spellings in the stock file.
		testing.expect_value(t, strings.count(strings.to_lower(block, context.temp_allocator), "groupbrally"), 1)
	}
	testing.expect(t, strings.contains(out, `<track value="battersea" />`), "a track line went missing")
}

@(test)
all_classes_runs_again_unchanged :: proc(t: ^testing.T) {
	once := d3.server_file_all_classes(SERVER_FILE, {"sportrally"})
	testing.expect_value(t, d3.server_file_all_classes(once, nil), once)
}
