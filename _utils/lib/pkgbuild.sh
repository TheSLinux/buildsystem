# Purpose: Provides `s-makepkg` a wrapper of ArchLinux `makepkg`
# Author : Anh K. Huynh
# License: GPL v2 (http://www.gnu.org/licenses/gpl-2.0.html)
# Date   : 2014 Apr 15th (moved from the original `run.sh`)
# Home   : https://github.com/TheSLinux/buildsystem/tree/_utils

:export s-makepkg _makepkg

# Reset some environments' variables and load the PKGBUILD file in
# the current working directory, or return error (127).
#
# Input
#   _s_env
#
# Output
#   New working environment
#
# FIXME: Add PACKAGE_CONFLICT_TYPE support
#
_pkgbuild_load() {
  _s_env || return 1

  if [[ -z "${PACKAGE_FEATURE}" || -z "${PACKAGE_FEATURE:1}" ]]; then
    _FEATURE_STRING=""
  else
    _FEATURE_STRING="${PACKAGE_FEATURE}"
  fi

  # IMPORTANTE NOTE
  #
  # Don't change the value of $_FEATURE_LIB32, because it is widely used.
  # There are only two case: 32, or <empty>
  # You've been warned.
  #
  echo "${PACKAGE_FEATURE}" | grep -q "lib32"
  if [[ $? -eq 0 ]]; then
    _FEATURE_LIB32="32"
  else
    _FEATURE_LIB32=""
  fi

  # FIXME: We should not mirror code like this. Need another way to
  # FIXME: patch `makepkg` and make code clean.
  unset pkgname pkgbase pkgver pkgrel epoch pkgdesc url license groups provides
  unset md5sums replaces depends conflicts backup source install changelog build
  unset makedepends optdepends options noextract

  pkgver="${PACKAGE_VERSION:-}"
  pkgrel="${PACKAGE_RELEASE:-}"
  pkgbase="${PACKAGE_BASE:-}"

  # Before this happends, the `/etc/makepkg.conf` or `~/.makepkg.conf` is
  # already loaded by `makepkg`. Because of this, some sanity check
  # for `makepkg.conf` settings can't be done in feature `makepkg.conf`.
  if [[ -n "${_FEATURE_STRING}" ]]; then

    if [[ -n "${_FEATURE_LIB32}" ]]; then
      export CHOST="i686-pc-linux-gnu"
      export CFLAGS="-m32 -march=i686 -mtune=generic -O2 -pipe -fstack-protector-strong --param=ssp-buffer-size=4 -D_FORTIFY_SOURCE=2"
      export CXXFLAGS="${CFLAGS}"
      export PKG_CONFIG_PATH="/usr/lib32/pkgconfig"
      export CXX="${CXX} -m32"
    fi

    if [[ -r "makepkg.conf${_FEATURE_STRING}" ]]; then
      source "makepkg.conf${_FEATURE_STRING}" || return
    fi
  fi

  # Set some shell options as same as ArchLinux (makepkg#source_safe)
  shopt -u extglob # FIXME: why?
  source "PKGBUILD" || return
  if [[ -n "${_FEATURE_STRING}" && -f "PKGBUILD${_FEATURE_STRING}" ]]; then
    source "PKGBUILD${_FEATURE_STRING}" || return
  fi
  shopt -s extglob # FIXME: why?

  if [[ -z "${pkgname-}" ]]; then
    pkgname=("$PACKAGE_BASE")
  fi

  # Convert $pkgname to an array if it is a string!
  { declare -p 'pkgname' \
    | grep -qE '^declare \-a ' ; } \
  || pkgname=($pkgname)

  pkgbase=${pkgbase:-${PACKAGE_BASE}}

  if [[ "${PACKAGE_FEATURE:0:1}" == "@" ]]; then
    conflicts=("${conflicts[@]:-}" "$pkgname")
    provides=("${provides[@]:-}" "$pkgname")
  fi

  if [[ -n "${_FEATURE_LIB32}" ]]; then
    pkgdesc="${pkgdesc} [lib32]"
    provides=("lib32-${PACKAGE_BASE}" "${PACKAGE_BASE}%lib32" "${provides[@]:-}")
    conflicts=("lib32-${PACKAGE_BASE}" "${PACKAGE_BASE}%lib32" "${conflicts[@]:-}")
  fi

  _pkgbuild_s_sources >/dev/null
}

# Return the list of sources on #theslinux mirror.
# This function will load `PKGBUILD if `PACKAGE_BASE is not defined.
# The variable `source` will be updated.
#
# NOTES: If the URI is of the form "foobar::URI", the "foobar" is used
# NOTES: on our source. For this reason, you should use a variant
# NOTES: filename for "foobar". For example,
# NOTES:    Bad:  foobar.tgz::http://example.net/foo-bar-1.2.3.tgz
# NOTES:    Good: foobar-1.2.3.tgz::http://example.net/foo-bar-1.2.3.tgz
_pkgbuild_s_sources() {
  local _sources=()
  local _basename=
  local _uri=
  local _first_c=

  [[ -z "${WITHOUT_THESLINUX_SOURCES:-}" ]] || return 0

  _first_c="${PACKAGE_BASE:0:1}"
  _first_c="${_first_c,}"
  _sources=("${source[@]}")
  source=()

  for __ in "${_sources[@]}"; do
    echo "${__}" | grep -q '://' \
    || {
      source+=("${__}")
      continue
    }
    echo "${__}" | grep -Eq '\.sig$' && continue
    echo "${__}" | grep -Eq '\.asc$' && continue
    echo "${__}" | grep -q '::' \
    && {
      _basename="${__%%::*}"
    } \
      || _basename="${__##*/}"

    _uri="http://f.theslinux.org/s/${_first_c}/${PACKAGE_BASE}/${_basename}"
    source+=("${_uri}" "${_uri}.asc")
  done
}

# This script will read the PKGBUILD from the current build environment
# and print YAML contents that describe some basic information of the
# package. The primary purpose is to gather information from packages
# quicly and simple. We also build our own hierachy of dependencies.
#
# Input
#   Current build environment that's detected by `_s_env`
#
# Output
#   YAML string should be checked by a 3rd party method
#   Always return 0. See also `_pkgbuild_to_yaml_with_check`
#
# FIXME: Add PACKAGE_CONFLICT_TYPE support
#
_pkgbuild_to_yaml() {
  _pkgbuild_load || return

  cat <<EOF
---
$PACKAGE_BASE:
  version: "$PACKAGE_VERSION"
  description: "$pkgdesc"
  feature: "$PACKAGE_FEATURE"
  url: "$url"
  license: "${license[@]}"
EOF

  [[ -z "${pkgname}" ]] \
    && echo "  packages:" \
    && for _u in "${pkgname[@]}"; do echo "  - $_u"; done

  [[ -n "${sources}" ]] \
    && echo "  sources:" \
    && for _u in "${source[@]}"; do echo "  - $_u"; done

  [[ -n "${conflicts}" ]] \
    && echo "  conflicts:" \
    && for _u in "${conflicts[@]}"; do echo "  - $_u"; done

  [[ -n "${provides}" ]] \
    && echo "  provides:" \
    && for _u in "${provides[@]}"; do echo "  - $_u"; done

  [[ -n "${replaces}" ]] \
    && echo "  replaces:" \
    && for _u in "${replaces[@]}"; do echo "  - $_u"; done

  [[ -n "${makedepends}" ]] \
    && echo "  makedepends:" \
    && for _u in "${makedepends[@]}"; do echo "  - $_u"; done

  [[ ! -f "$install" ]] \
    && [[ -f "${PACKAGE_BASE}.install" ]] \
    && install="${PACKAGE_BASE}.install" \
    || install=""

  # The contents of `install` script will be shipped with the package
  # FIXME: If a sub-package provides its own `install` script we can not
  # FIXME: detect the script here. Should find another way.
  [[ -z "$install" ]] \
  || {
    echo "  install: |"
    cat "$install" | awk '{printf("    %s\n", $0)}'
  }

  : 'This function often returns successfully'
}

# Check the output of `_pkgbuild_to_yaml` with Ruby/YAML
# The output of this command is often more compact that the original
# output of `_pkgbuild_to_yaml`.
#
# Input
#   As same as `_pkgbuild_to_yaml`
#
# Output
#   error || Valid YAML file
#
# FIXME: A valid PKGBUILD should containn some basic fields like
# FIXME: package name, version, build script,... The check should know
# FIXME: this and return error if there is any missing field
#
# FIXME: What happends if we have 10,000 packages to check!?
#
_pkgbuild_to_yaml_with_check() {
  _pkgbuild_to_yaml "$@" \
  | ruby -ryaml -e "puts YAML.dump(YAML.load(STDIN))"
}

# TheSLinux's version of Arch makepkg. This will check and generate
# some environment variables before invoking the real program `makepkg`.
# Note: the dash (-) hides this function from Geany symbols listing
#
# Difference from the original `makepkg`
#
# 1. Package information {name, version, release} can be provided
#    externally (from the environment)
# 2. `PKGBUILD` should provide metadata and build process, it doesn't
#    contain any real data (version number, checksums,..)
# 3. The default hash is `sha512` (this's part of `pacman` though)
# 4. Can build any version of package quickly without modifying the
#    `PKGBUILD`. However, some `PKGBUILD` may only work with a limit
#    set of versions (if this is the case, we may split `PKGBUILD`
#    into parts.)
# 5. `Release number` is detected automatically
# 6. `PKGBUILD` isn't independent and it can't be used with the original
#    `makepkg` without some environment settings
# 7. Doesn't support version string that only has one number. E.g,
#    the package `xterm` or `less` only uses one number (patch number).
#    This is possibly due to history reason. This number will be converted
#    to two number forms by adding zero `0` to the original string. E.g,
#    `xterm-291-1` should read `xterm-0.291-1`.
# 8. `PACKAGE_BASE` (so `pkgbase`) is alway defined.
# 9. `PACKAGE_FEATURE` helps to provide package name with any special
#    feature, without creating "official branch". We just need to
#    create a feature branch and `_makepkg` will use the branch name
#    as `PACKAGE_FEATURE`, and will append the string to name of the
#    final output package. It also helps to modify the variables
#    `conflicts`, `provides`,... on-the-fly.
#    `PACKAGE_FEATURE` must be prefixed with an modifier ([@%=+#]).
#    See `_get_package_name` for details.
#
_makepkg() {
  _s_env || return 1
  which makepkg >/dev/null || return
  source $(which makepkg) "$@"
}

# Execute the `get_update` function from PKGBUILD. If the function
# does not exist, an error will occur. Assume that we are in right
# directory (this is true if `_s_env` runs  well) that has PKGBUILD
_get_update() {
  _s_env || return 1
  unset "get_update" || return 1
  _pkgbuild_load
  get_update
}

# </source>
#
