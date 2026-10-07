package nefs

// NeFS 1.5.1 as DiRT 3 ships it in win_000.nfs: an RSA-signed intro, then an
// AES-256-ECB header and data, no compression. Layout from NefsLib
// (github.com/victorbush/ego.nefsedit); game addresses from dirt3_game.exe.
//
// `rebuild` lays every file out again, so a file can change size. The header
// then changes, so the result is signed with our key, not Codemasters'.

import "core:crypto/aes"
import "core:encoding/endian"
import "core:encoding/hex"
import "core:fmt"
import "core:hash"
import "core:math/big"
import "core:slice"

// DiRT 3's public modulus (exe VA 0xeab668), little-endian.
STOCK_N := [128]u8 {
	0xe1, 0x20, 0x90, 0x92, 0xb1, 0x24, 0xe2, 0xf4, 0x98, 0xba, 0xc1, 0xf4, 0x8e, 0xf9, 0x26, 0x5b,
	0x16, 0xfd, 0x24, 0xa4, 0xb7, 0xd6, 0x64, 0xb0, 0xd7, 0xa4, 0x56, 0x8d, 0x46, 0x95, 0xcb, 0x0c,
	0xd1, 0x1a, 0x63, 0x66, 0x1d, 0x96, 0x08, 0x43, 0x2b, 0xc0, 0xcc, 0xfa, 0x74, 0xa5, 0xde, 0x1f,
	0x8b, 0x8a, 0x68, 0x3a, 0xde, 0xc9, 0x72, 0x45, 0x91, 0x07, 0x4b, 0x4a, 0xc4, 0x05, 0x0e, 0xe4,
	0x81, 0xb0, 0x5d, 0x52, 0x79, 0x39, 0x0d, 0x09, 0xae, 0xb0, 0x9d, 0xf7, 0xcc, 0x09, 0xa1, 0xc9,
	0x8e, 0xfb, 0x24, 0xe7, 0x1e, 0xc7, 0xac, 0x6d, 0x88, 0x90, 0x0b, 0x12, 0x71, 0x34, 0x1c, 0xc4,
	0x2b, 0x8f, 0xdc, 0x4d, 0x70, 0x17, 0x30, 0x38, 0x5c, 0xf2, 0xfb, 0xc9, 0x84, 0xa1, 0xe7, 0xc9,
	0x06, 0x14, 0x35, 0xd9, 0x1e, 0xf4, 0x7e, 0x98, 0xe9, 0x4e, 0x56, 0x35, 0xba, 0x23, 0x14, 0x8c,
}

// Our modulus: the prime 2^1023 + 1155. A prime n gives d from n alone, so
// there is no secret. It only has to be the same on every install.
OUR_N := [128]u8 {
	0x83, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80,
}

// 65537^-1 mod (n - 1).
@(private = "file")
OUR_D := [128]u8 {
	0x11, 0x97, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c,
	0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c,
	0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c,
	0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c,
	0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c,
	0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c,
	0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c,
	0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c, 0x3c, 0x93, 0xc3, 0x6c,
}

@(private = "file")
MAGIC :: 0x5346654E // "NeFS"
@(private = "file")
VERSION :: 0x10501
@(private = "file")
E :: 65537
// The last block of a file is padded to this.
@(private = "file")
FILE_ALIGN :: 128
@(private = "file")
AES_TRANSFORM :: 4

Signer :: enum {
	Stock,
	Ours,
}

Archive :: struct {
	raw:       []u8,
	header:    []u8, // decrypted, addressed like the game's own copy
	words:     [32]u32, // the unscrambled intro
	signed_by: Signer,
	aes:       aes.Context_ECB,
}

// A replacement: a bare file name and its new plaintext.
File :: struct {
	name: string,
	data: []u8,
}

// A file of the archive and where its header records sit.
@(private = "file")
Item :: struct {
	name:          string,
	entry, shared: int, // header offsets
	start, size:   int,
	first, last:   int, // block range [first, last)
}

open :: proc(raw: []u8) -> (a: Archive, msg: string, ok: bool) {
	if len(raw) < 128 {
		return a, "archive is too short", false
	}
	a.raw = raw
	found := false
	for signer in Signer {
		key := signer == .Stock ? STOCK_N : OUR_N
		if intro, decoded := rsa(raw[:128], key[:], nil); decoded {
			a.words = intro_words(intro)
			unscramble(&a.words)
			if a.words[0] == MAGIC && a.words[2] == VERSION {
				a.signed_by, found = signer, true
				break
			}
		}
	}
	w := &a.words
	header_size := int(w[1])
	if !found || header_size > len(raw) || (header_size - 128) % 16 != 0 || w[3] != 1 {
		return a, "not a DiRT 3 NeFS 1.5.1 archive signed by Codemasters or by us", false
	}

	intro := intro_bytes(w^)
	key, key_ok := hex.decode(intro[0x3C:0x7C], context.temp_allocator)
	if !key_ok {
		return a, "archive key is not hex", false
	}
	aes.init_ecb(&a.aes, key)

	// The game copies 126 intro bytes, then decrypts the rest right after them.
	a.header = make([]u8, header_size - 2)
	copy(a.header, intro[:126])
	ecb(&a.aes, a.header[126:], raw[128:header_size], decrypt = true)
	return a, "", true
}

close :: proc(a: ^Archive) {
	delete(a.header)
	aes.reset_ecb(&a.aes)
}

read :: proc(a: ^Archive, name: string, allocator := context.allocator) -> (data: []u8, ok: bool) {
	for it in items(a) {
		if it.name == name {
			return decrypt_item(a, it, allocator), true
		}
	}
	return
}

// The TOC checksum and every block CRC16 match what the header holds.
checks_hold :: proc(a: ^Archive) -> bool {
	if toc_checksum(a.header) != a.words[14] {
		return false
	}
	for it in items(a) {
		for b in it.first ..< it.last {
			s, e := block_range(a, it, b)
			if crc16(a.raw[s:e]) != block_crc(a.header, a.words, b) {
				return false
			}
		}
	}
	return true
}

// The archive again with `replace` swapped in (bare name -> plaintext), signed
// with our key. A replacement that changes a file's block count is refused.
rebuild :: proc(a: ^Archive, replace: []File, allocator := context.allocator) -> (out: []u8, msg: string, ok: bool) {
	w := a.words
	header := slice.clone(a.header, context.temp_allocator)
	list := items(a)
	slice.sort_by(list, proc(x, y: Item) -> bool {return x.first < y.first})
	for r in replace {
		if !has_item(list, r.name) {
			return nil, fmt.tprintf("%s is not in the archive", r.name), false
		}
	}

	volume := int(w[11])
	data_offset := int(endian.unchecked_get_u32le(header[volume + 12:]))
	block_size := int(w[5])
	buf := make([dynamic]u8, allocator)
	append(&buf, ..a.raw[:data_offset])

	for it in list {
		plain := replacement(replace, it.name) or_else decrypt_item(a, it, context.temp_allocator)
		blocks := max(1, (len(plain) + block_size - 1) / block_size)
		if blocks != it.last - it.first {
			delete(buf)
			return nil, fmt.tprintf("%s would need %d blocks, the header has room for %d", it.name, blocks, it.last - it.first), false
		}
		start := len(buf)
		for k in 0 ..< blocks {
			chunk := plain[k * block_size:min((k + 1) * block_size, len(plain))]
			padded := make([]u8, (len(chunk) + FILE_ALIGN - 1) / FILE_ALIGN * FILE_ALIGN, context.temp_allocator)
			copy(padded, chunk)
			ecb(&a.aes, padded, padded)
			append(&buf, ..padded)

			b := block_table(w) + 8 * (it.first + k)
			if endian.unchecked_get_u16le(header[b + 4:]) != AES_TRANSFORM {
				delete(buf)
				return nil, fmt.tprintf("%s: block %d is not plain AES", it.name, it.first + k), false
			}
			endian.unchecked_put_u32le(header[b:], u32(len(buf) - start))
			endian.unchecked_put_u16le(header[b + 6:], crc16(padded))
		}
		endian.unchecked_put_u64le(header[it.entry:], u64(start))
		endian.unchecked_put_u32le(header[it.shared + 16:], u32(len(plain)))
	}
	for len(buf) % block_size != 0 {
		append(&buf, 0)
	}
	endian.unchecked_put_u64le(header[volume:], u64(len(buf)))

	w[14] = toc_checksum(header)
	endian.unchecked_put_u32le(header[0x38:], w[14])
	header_size := int(w[1])
	ecb(&a.aes, buf[128:header_size], header[126:])
	scramble(&w)
	n, d := OUR_N, OUR_D
	intro := intro_bytes(w)
	signed, signed_ok := rsa(intro[:], n[:], d[:])
	if !signed_ok {
		delete(buf)
		return nil, "could not sign the header", false
	}
	copy(buf[:128], signed[:])
	return buf[:], "", true
}

// The CRC16 the game samples: both halves of the ciphertext's CRC32, added.
crc16 :: proc(cipher: []u8) -> u16 {
	c := hash.crc32(cipher)
	return u16(c) + u16(c >> 16)
}

// dirt3_game.exe 0x78f8d0: the intro up to the checksum, then the rest past it.
@(private = "file")
toc_checksum :: proc(header: []u8) -> u32 {
	return hash.crc32(header[0x3C:], hash.crc32(header[:0x38]))
}

@(private = "file")
items :: proc(a: ^Archive) -> []Item {
	w, h := a.words, a.header
	entries, shared, names := int(w[7]), int(w[8]), int(w[9])
	out := make([dynamic]Item, context.temp_allocator)
	for i in 0 ..< int(w[4]) {
		e := entries + 24 * i
		if endian.unchecked_get_u16le(h[e + 10:]) & 2 != 0 { // a directory
			continue
		}
		s := shared + 28 * int(endian.unchecked_get_u32le(h[e + 12:]))
		append(&out, Item {
			name = cstring_at(h, names + int(endian.unchecked_get_u32le(h[s + 12:]))),
			entry = e,
			shared = s,
			start = int(endian.unchecked_get_u64le(h[e:])),
			size = int(endian.unchecked_get_u32le(h[s + 16:])),
			first = int(endian.unchecked_get_u32le(h[e + 16:])),
		})
	}
	// A file's blocks run until the next file's first block.
	n_blocks := (int(w[11]) - block_table(w)) / 8
	for &it in out {
		it.last = n_blocks
		for other in out {
			if other.first > it.first && other.first < it.last {
				it.last = other.first
			}
		}
	}
	return out[:]
}

@(private = "file")
has_item :: proc(list: []Item, name: string) -> bool {
	for it in list {
		if it.name == name {
			return true
		}
	}
	return false
}

@(private = "file")
replacement :: proc(replace: []File, name: string) -> ([]u8, bool) {
	for r in replace {
		if r.name == name {
			return r.data, true
		}
	}
	return nil, false
}

@(private = "file")
block_table :: proc(w: [32]u32) -> int {
	return int(w[10])
}

@(private = "file")
block_end :: proc(header: []u8, w: [32]u32, b: int) -> int {
	return int(endian.unchecked_get_u32le(header[block_table(w) + 8 * b:]))
}

@(private = "file")
block_crc :: proc(header: []u8, w: [32]u32, b: int) -> u16 {
	return endian.unchecked_get_u16le(header[block_table(w) + 8 * b + 6:])
}

@(private = "file")
block_range :: proc(a: ^Archive, it: Item, b: int) -> (start, end: int) {
	prev := b > it.first ? block_end(a.header, a.words, b - 1) : 0
	return it.start + prev, it.start + block_end(a.header, a.words, b)
}

@(private = "file")
decrypt_item :: proc(a: ^Archive, it: Item, allocator := context.allocator) -> []u8 {
	s, _ := block_range(a, it, it.first)
	_, e := block_range(a, it, it.last - 1)
	plain := make([]u8, e - s, allocator)
	ecb(&a.aes, plain, a.raw[s:e], decrypt = true)
	return plain[:it.size]
}

@(private = "file")
ecb :: proc(ctx: ^aes.Context_ECB, dst, src: []u8, decrypt := false) {
	for i := 0; i < len(src); i += 16 {
		if decrypt {
			aes.decrypt_ecb(ctx, dst[i:i + 16], src[i:i + 16])
		} else {
			aes.encrypt_ecb(ctx, dst[i:i + 16], src[i:i + 16])
		}
	}
}

@(private = "file")
cstring_at :: proc(data: []u8, at: int) -> string {
	end := at
	for end < len(data) && data[end] != 0 {
		end += 1
	}
	return string(data[at:end])
}

@(private = "file")
intro_bytes :: proc(w: [32]u32) -> (out: [128]u8) {
	for word, i in w {
		endian.unchecked_put_u32le(out[4 * i:], word)
	}
	return
}

@(private = "file")
intro_words :: proc(b: [128]u8) -> (w: [32]u32) {
	b := b
	for &word, i in w {
		word = endian.unchecked_get_u32le(b[4 * i:])
	}
	return
}

// Raw RSA, no padding, little-endian both ways. No `d` means e = 65537.
@(private = "file")
rsa :: proc(input, modulus, d: []u8) -> (out: [128]u8, ok: bool) {
	m, e, n, r := &big.Int{}, &big.Int{}, &big.Int{}, &big.Int{}
	defer big.destroy(m, e, n, r)
	set_e := d == nil ? big.set(e, E) : big.int_from_bytes_little(e, d)
	if set_e != nil ||
	   big.int_from_bytes_little(m, input) != nil ||
	   big.int_from_bytes_little(n, modulus) != nil ||
	   big.internal_int_exponent_mod(r, m, e, n) != nil ||
	   big.int_to_bytes_little(r, out[:]) != nil {
		return
	}
	return out, true
}

// dirt3_game.exe 0x78f800.
@(private = "file")
unscramble :: proc(w: ^[32]u32) {
	w[14] ~= w[5]; w[5] ~= w[2]; w[2] ~= w[4]; w[4] ~= w[7]; w[7] ~= w[3]
	w[3] ~= w[9]; w[9] ~= w[10]; w[10] ~= w[1]; w[1] ~= w[13]; w[13] ~= w[11]
	w[11] ~= w[0]; w[0] ~= w[12]; w[12] ~= w[6]; w[6] ~= w[8]; w[8] ~= w[14]
	for i in 15 ..< 31 {
		w[i] ~= w[14]
	}
}

@(private = "file")
scramble :: proc(w: ^[32]u32) {
	for i in 15 ..< 31 {
		w[i] ~= w[14]
	}
	w[8] ~= w[14]; w[6] ~= w[8]; w[12] ~= w[6]; w[0] ~= w[12]; w[11] ~= w[0]
	w[13] ~= w[11]; w[1] ~= w[13]; w[10] ~= w[1]; w[9] ~= w[10]; w[3] ~= w[9]
	w[7] ~= w[3]; w[4] ~= w[7]; w[2] ~= w[4]; w[5] ~= w[2]; w[14] ~= w[5]
}
