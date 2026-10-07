# d3acat

Any car, any track in DiRT 3 Complete Edition, also in online races. It
works with modded installs, for example DiRT 3 Reloaded and dirtbench venues.

## Use

Put `d3acat` in the game directory (the directory with `dirt3_game.exe`) and
run it from there. Alternatively, give the directory with `--game`.

```
d3acat                              any car on any track, online too
d3acat --class sport_rally          also add a class from the database to every mode
d3acat --game <dir>                 the game directory, if it is not the current one
d3acat --restore                    put the stock files back
d3acat --version | --license | --credits | --readme
```

**LINUX**: before the first run, do `chmod +x d3acat`.

All players in an online race must have the same files. At the end of each
run, d3acat shows the CRC32 of each file that it changes. Compare these
values with the other players.

If you install a mod or deploy a dirtbench venue, run d3acat again after it.
A second run with no new changes does nothing.

## What it changes

| File | Change |
|---|---|
| `dirt3_game.exe`, `dirt3_bench.exe` | The RSA modulus that checks `win_000.nfs` (128 bytes at VA `0xeab668`) becomes ours. |
| `database/database.bin` | Each table that pairs classes with modes gets a row for each class in each mode that it already lists: `sr_vehicle_class_discipline`, `tt_vehicle_class_disciplines`, `eligible_vehicle_classes` and `net_vehicle_class_restrictions`. |
| `win_000.nfs` → `server_file.xml` | Each online race type lists each vehicle class. |
| `win_000.nfs` → `csconfig.xml`, `csdata.xml` | The checksum manager checks no file. This is the same blanking that dirtbench does, and the files keep their length. |

d3acat writes the first change to a file only when all of the new files are
ready. Before the first write, it copies each file to `<file>.orig`.
`--restore` copies the `.orig` files back.

`--class <name>` takes the `file_string` of a `vehicle_class` row. If the class
has no single-race class or network class, d3acat adds them. Its name in
`server_file.xml` is the name without `_`, so `sport_rally` becomes
`sportrally`.

## Why the key changes

`win_000.nfs` is a NeFS 1.5.1 archive. Its header is RSA-signed and holds the
size and CRC16 of each data block. When `server_file.xml` gets longer, the
header changes, so the stock signature is no longer correct. d3acat builds
the archive again and signs it with its own key. The exe then checks the
archive with this key.

The key is not secret. Its modulus is the prime 2^1023 + 1155, so anyone can
calculate the private exponent from it. The key only has to be the same on
each install. The code self-check of the game reads `.text` in memory only,
so a change on disk to `.rdata` passes it.

## Not proven in the game

- Online play with modded files and the blanked checksums.
- The names that `server_file.xml` uses for classes. The stock file has
  `OpenClassicTrailblazer` for the class with `net_type`
  `modern_classic_trailblazer`, so the game possibly does not use the
  `net_type` to find a class.
- A class in a mode that it was not made for, for example rally cars in
  gymkhana.

## dirtbench

dirtbench reads and writes `win_000.nfs` only when it has the stock
signature. If dirtbench changes the archive after d3acat, run d3acat again.
d3acat keeps the dirtbench changes and signs the archive again.

## Build

```
./test.sh               every test suite
./release.sh --local    -> build/d3acat
./release.sh --public --version 0.1.0 --notes "notes"
```

The tests that need game files read the install in `DIRT3_DIR` (see
`tests/game.odin`). Without it, they stop and report a skip.

## Thanks

- [Victor Bush](https://github.com/victorbush), for
  [NefsEdit](https://github.com/victorbush/ego.nefsedit) and the NeFS layout.
- The [Ego-Engine-Modding](https://github.com/EgoEngineModding/Ego-Engine-Modding)
  team, for the database schema.
- [ismellyu](https://github.com/ISmellYu), for
  [Grid2Bypass](https://github.com/ISmellYu/Grid2Bypass), which mapped the code
  self-check.

## License

MIT, see `LICENSE`. Third-party data is listed in `credits.txt`.
