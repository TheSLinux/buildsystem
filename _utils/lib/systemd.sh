# Purpose: Provide some shortcuts for systemd
# Author : Anh K. Huynh
# License: GPL v2 (http://www.gnu.org/licenses/gpl-2.0.html)
# Date   : 2014 May 2nd
# Home   : https://github.com/TheSLinux/buildsystem/tree/_utils

# This is a shortcut of `systemctl`. Instead of typing a long command
# (who wants `sudo systemctl status MyDnsDaemon` ?), user only needs
# to type a short string (`sudo status MyDnsDaemon`).
_systemd_ctl() {
  systemctl "$@"
}
