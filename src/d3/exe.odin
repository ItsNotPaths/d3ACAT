package d3

// The exe holds the RSA modulus that checks win_000.nfs (VA 0xeab668, .rdata).
// The code self-check covers .text in memory only, so a patch on disk passes.

import "core:bytes"
import "../nefs"

GAME_EXES := [?]string{"dirt3_game.exe", "dirt3_bench.exe"}

// `data` with our modulus in place of Codemasters'. Nil when it is already ours.
exe_rekey :: proc(data: []u8) -> (out: []u8, msg: string, ok: bool) {
	stock, ours := nefs.STOCK_N, nefs.OUR_N
	if bytes.count(data, ours[:]) == 1 {
		return nil, "", true
	}
	at := bytes.index(data, stock[:])
	if at < 0 || bytes.count(data, stock[:]) != 1 {
		return nil, "the stock key is not in it exactly once: unknown exe build", false
	}
	out = bytes.clone(data, context.temp_allocator)
	copy(out[at:], ours[:])
	return out, "", true
}
