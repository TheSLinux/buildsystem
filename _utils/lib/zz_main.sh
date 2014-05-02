# Purpose: The main routine, that invokes user's function
# Author : Anh K. Huynh
# License: GPL v2 (http://www.gnu.org/licenses/gpl-2.0.html)
# Date   : 2014 Apr 15th (moved from the original `run.sh`)
# Home   : https://github.com/TheSLinux/buildsystem/tree/_utils

set -u

unset GREP_OPTIONS || _die "Unable to unset 'GREP_OPTIONS'"
unset _func || _die "Unable to update '_func' variable"

case "${0##*/}" in
  "s-import-package") _func="_import_packages" ;;
  "s-makepkg")        _func="_makepkg" ;;
  "start")            _func="_systemd_ctl start" ;;
  "stop")             _func="_systemd_ctl stop" ;;
  "status")           _func="_systemd_ctl status" ;;
  *)                  _func="" ;;
esac

[[ -n "$_func" ]] || (( $# )) || _die "Missing arguments"

$_func "$@"
