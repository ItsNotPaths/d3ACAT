package main

import "core:fmt"
import "core:os"
import "../d3"

// Stamped at build time by release.sh and the release workflow. Each comes in
// behind a "_", or Odin reads an all-digit commit as an integer.
VERSION :: #config(D3ACAT_VERSION, "_dev")[1:]
COMMIT :: #config(D3ACAT_COMMIT, "_unknown")[1:]

LICENSE_TEXT :: #load("../../LICENSE", string)
CREDITS_TEXT :: #load("../../credits.txt", string)
README_TEXT :: #load("../../README.md", string)

USAGE :: `usage: d3acat [--game <DiRT 3 dir>] [--class <vehicle_class>]... [--restore]

  no flags            any car on any track, online too, in the current directory
  --game <dir>        the DiRT 3 directory, if it is not the current one
  --class <name>      also add this vehicle_class (file_string) to every mode,
                      for example sport_rally from DiRT 3 Reloaded
  --restore           put the .orig files back
  --version | --license | --credits | --readme`

main :: proc() {
	args := os.args[1:]
	if len(args) == 1 do switch args[0] {
	case "--version":
		fmt.printfln("d3acat %s (%s)", VERSION, COMMIT)
		return
	case "--license":
		fmt.printfln("d3acat %s (%s)\n", VERSION, COMMIT)
		fmt.println(LICENSE_TEXT)
		return
	case "--credits":
		fmt.println(CREDITS_TEXT)
		return
	case "--readme":
		fmt.println(README_TEXT)
		return
	}

	game := "."
	restore := false
	classes := make([dynamic]string)
	for i := 0; i < len(args); i += 1 {
		switch {
		case args[i] == "--restore":
			restore = true
		case args[i] == "--game" && i + 1 < len(args):
			game = args[i + 1]
			i += 1
		case args[i] == "--class" && i + 1 < len(args):
			append(&classes, args[i + 1])
			i += 1
		case:
			fmt.eprintln(USAGE)
			os.exit(2)
		}
	}
	msg: string
	ok: bool
	if restore {
		msg, ok = d3.restore(game)
	} else {
		msg, ok = d3.apply(game, classes[:])
	}
	if !ok {
		fmt.eprintln(msg)
		os.exit(1)
	}
}
