package tests

import "core:bytes"
import "core:testing"
import "../src/nefs"

@(test)
stock_archive_reads :: proc(t: ^testing.T) {
	raw, found := game_file(t, "win_000.nfs")
	if !found {
		return
	}
	a, msg, ok := nefs.open(raw)
	defer nefs.close(&a)
	testing.expectf(t, ok, "open: %s", msg)
	testing.expect_value(t, a.signed_by, nefs.Signer.Stock)
	testing.expect(t, nefs.checks_hold(&a), "stock header checks do not hold")
	data, has := nefs.read(&a, "server_file.xml", context.temp_allocator)
	testing.expect(t, has)
	testing.expect_value(t, len(data), 31217)
}

// A file can change size; the result is ours, passes every game check, and
// leaves every other file as it was.
@(test)
rebuild_takes_a_new_size :: proc(t: ^testing.T) {
	raw, found := game_file(t, "win_000.nfs")
	if !found {
		return
	}
	stock, _, _ := nefs.open(raw)
	defer nefs.close(&stock)
	text, _ := nefs.read(&stock, "server_file.xml", context.temp_allocator)
	grown := make([]u8, len(text) + 5000, context.temp_allocator)
	copy(grown, text)
	for &b in grown[len(text):] {
		b = ' '
	}

	out, msg, ok := nefs.rebuild(&stock, {{"server_file.xml", grown}}, context.temp_allocator)
	testing.expectf(t, ok, "rebuild: %s", msg)

	a, open_msg, opened := nefs.open(out)
	defer nefs.close(&a)
	testing.expectf(t, opened, "reopen: %s", open_msg)
	testing.expect_value(t, a.signed_by, nefs.Signer.Ours)
	testing.expect(t, nefs.checks_hold(&a), "rebuilt header checks do not hold")
	for name in ([]string{"anti_cheat.xml", "csconfig.xml", "csdata.xml", "statsdef.bin", "matchmaking.bin", "safety_rating_config.xml", "race_session_filter_config.xml", "richpresenceinfo.bin"}) {
		before, _ := nefs.read(&stock, name, context.temp_allocator)
		after, has := nefs.read(&a, name, context.temp_allocator)
		testing.expectf(t, has && bytes.equal(before, after), "%s changed", name)
	}
	back, _ := nefs.read(&a, "server_file.xml", context.temp_allocator)
	testing.expect(t, bytes.equal(back, grown), "server_file.xml did not come back")
}
