# CastControl v0.1.0

A simple macOS menu bar utility for quickly managing presentation-related display settings.

This is an early personal project, built to reduce the need to open System Settings every time you want to switch between mirrored and extended displays, arrange external screens, select display audio output, or hide desktop clutter while presenting.

## Features

* Switch external displays between mirror and extend modes
* Choose whether mirroring should fit the external display or match the Mac display
* Arrange extended displays from a simple utility window
* Select a compatible external display as the system sound output
* Hide or show desktop icons and widgets
* Open macOS Display Settings quickly
* Runs as a lightweight menu bar app

## Why...

I often connect my Mac to external displays, but switching between duplicate/mirror and extend mode through System Settings is annoying so I made this as quick access to the controls I actually use.

## Requirements

* macOS
* Xcode

## Build

No signed release build is currently provided. To try CastControl, clone the repository and build it in Xcode.

1. Open `CastControl.xcodeproj` in Xcode.
2. Select the `CastControl` scheme.
3. Choose your Mac as the run destination.
4. Build and run with `Cmd-R`.

## Notes

CastControl changes system-level display and desktop settings. Some behaviour may depend on macOS version, connected display type, Sidecar/AirPlay behaviour, and available system APIs.

Hiding desktop clutter changes global macOS desktop settings for icons and widgets. CastControl stores the previous values and restores them when clutter is shown again or the app quits, but Finder and the desktop may briefly refresh when those settings are applied.

As of testing with macOS 26, the system may expose mirrored displays differently from extended displays. If an external display is first connected while already in Mirror mode, CastControl may initially show a generic name such as “Display 2” instead of the monitor’s actual name. Switching to Extend mode once should allow CastControl to detect and cache the correct display name, after which it should continue using the better name when switching back to Mirror mode.

## License

This project is licensed under the GNU General Public License v3.0.
