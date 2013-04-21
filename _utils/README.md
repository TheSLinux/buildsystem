## Purpose

This branch `_utils` provides some utils for `TheSLinux` developers.
The source of this utils is found in [2].

## License. Author

The work is distributed under the license GPL2 [1].
The original author is **Anh K. Huynh** from `TheSLinux`.

## Installation

There isn't package for this `_utils`. To install the utils, please refer
to the small file `Makefile`. You can type from your terminal

````
make install
# or make uninstall
````

This will install the three utils `s-run`, `s-makepkg` and `s-import-package`.

## s-run

This is the main script. It actually invokes the arguments you provide.
For example,

````
s-run echo "Hello, world."
````

is just another way to call `echo "Hello, world."`.

## s-makepkg

This is `TheSLinux` version of the original ArchLinux `makepkg`. This
script will set up the environment before invoking the real program
`makepkg`, and it is designed to work `TheSLinux` build system.

For example, to build the package `pacman` from `TheSLinux`
(Of course you can replace `pacman` by any package.)

````
$ git clone git://github.com/TheSLinux/buildsystem.git theslinux-buildsystem
$ cd theslinux-buildsystem
$ git checkout TheBigBang     # This is a must
$ git checkout pacman
$ cd pacman/
$ s-makepkg
````

**Note 1**: Because `s-makepkg` needs a special version of `pacman` [3],
you need to build and install `pacman` before any other package.

**Note 2**: We doesn't have support for `checksum`. In the mean time,
please use `--skipchecksums` when invoking `s-makepkg`.

## s-import-package

At this time this is a very `secret` script and it should be used by
the author. For more details, please discuss on the list or irc channel.

## Links

1. GPL version 2: http://www.gnu.org/licenses/gpl-2.0.html
2. Source page: https://github.com/TheSLinux/buildsystem/tree/_utils
3. Patch for pacman: https://github.com/TheSLinux/buildsystem/tree/pacman
