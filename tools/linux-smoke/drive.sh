#!/bin/bash
# Input drivers for tools/linux-smoke/launch.sh: what a person would do in the first seconds, sent as X11 events with xdotool to the
# app's window. There is no window manager in the virtual display, so a click goes to the window under the pointer and typed keys go
# to the window the pointer is over. Coordinates are relative to the window (the Flutter runner opens 1280x720 at 0,0).
# A driver that does not find what it expects fails quietly: the result is then the missing file, which the report shows.
# Sourced, not run.

click() { xdotool mousemove --window "$1" "$2" "$3" click 1; sleep 0.4; }

drive() { # NAME WINDOW
  case "$1" in
    none|"") : ;;
    *) "drive_$1" "$2" ;;
  esac
}

# calculator: 7 x 6 = (the display then reads 42; nothing is saved, this only shows that clicks reach the Flutter window)
drive_calculator() { click "$1" 168 388; click "$1" 1110 388; click "$1" 796 479; click "$1" 1110 662; }

# stopwatch: Start (the state file is written on every change)
drive_stopwatch() { click "$1" 563 224; }

# minesweeper: click a square to start a game, then another one (the saved game is written after every move)
drive_minesweeper() { click "$1" 640 392; click "$1" 520 272; }

# notepad: "Create a note", then type into the new note (autosave 600 ms after the last key)
drive_notepad() {
  click "$1" 780 394
  sleep 0.8
  xdotool type --delay 40 "Written on Linux under Xvfb"
}
