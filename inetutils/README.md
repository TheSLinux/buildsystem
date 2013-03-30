## Notes

This package provides the command `hostname` that's used by the command
`startx` (from the package `xorg-init`). The package `wicd` also requires
this package to work correctly.

The original ABS package has some utils (`rlogin`, `talk`) that I have
never used so I think those tools should be removed.

Please note that the package can be configured to provide some popular
commands `ping` and `ifconfig`. In this package those commands are disabled
(Why?), because `ping` comes from the package `iputils` and `ifconfig`
comes from the package `net-tools`.

## History

Import from ArchLinux's ABS

URL: svn://svn.archlinux.org/packages/inetutils/trunk
Revision: 180976
