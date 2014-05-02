# Purpose: Import ArchLinux PKGBUILD and create branch/tag in TBS
# Author : Anh K. Huynh
# License: GPL v2 (http://www.gnu.org/licenses/gpl-2.0.html)
# Date   : 2014 Apr 15th (moved from the original `run.sh`)
# Home   : https://github.com/TheSLinux/buildsystem/tree/_utils

:export s-import-package _import_packages

# Date   : 2013 March 30th
# Purpose: Import a package from ABS to current repository
# Usage  : $0 <package> <package> <package:arch-package-name>
#
# To import a package "foobar" in the buildsystem and use a new
# package name, you can use specify the alias as this example
#
#   $0  my-theslinux-package:archlinux-package
#   $0  special-systemd:systemd
#
# The script to find the package from a list of ABS directories,
# import ABS if there is no local branch for the package, create the
# very first tag for `_makepkg` if possible. New package will start
# from `TheSmallBang` branch.
#
# Directories:
#
#   a/   : Where to store ABS packages in the structure
#             <package-1>/trunk/
#             <package-2>/trunk
#          This is because ABS is in SVN structure, and the most
#          development stuff is in the directory `/trunk/`
#
#   b/   : Similar to `a/`, but for :community packages
#
#   ./   : where to import new package; this is often the root
#          directory of the :builssystem.
#
# If you are new to our buildsystem, please try as below
#
#   $ git clone https://github.com/TheSLinux/buildsystem.git
#   $ cd buildsystem
#   $ svn checkout --depth=empty svn://svn.archlinux.org/community b
#   $ svn checkout --depth=empty svn://svn.archlinux.org/packages  a
#
# You may use the "ABS" environment to specify list of directories
# where our script looks up for the Arch packages information.
#
_import_package() {
  local _pkg="${1-}:"                 # package name + :
  local _apkg=":${1-}"                # : + (arch) package name
  local _ds=""                        # path to Arch package/trunk
  local _dd=""                        # destination on our buildsystem
  local _rev=                         # package revision (SVN)
  local _f_readme=""                  # our README file
  local _pkgver=
  local _D_ABS="${ABS:-$PWD/a/ $PWD/b/}"

  _pkg="${_pkg%%:*}"                  # the first part, splitted by :
  _apkg="${_apkg##*:}"                # the last part, splitted by :
  _apkg="${_apkg:-$_pkg}"             # by default, _pkg  == _apkg
  _dd="$PWD/$_pkg/"

  _msg ">> Trying to import package $_pkg (from Arch '$_apkg' package) <<"

  [[ ! -d "$_dd/" ]] \
  || { _err "Directory does exist $_dd"; return 1; }

  # Find the first ABS source that contains `$_apkg`
  for _ds in $_D_ABS; do
    [[ ! -d "$_ds/$_apkg/trunk/" ]] || break
  done

  # If we don't find any $_pkg in current list of sources
  # we will try to invoke `svn update` in every source. Please note that
  # the command `svn update non-existent-package` will return 0 even if
  # the package doesn't exist in the ArchLinux's ABS system. There is
  # two ways to check if there is a package: `svn ls` and `svn update`.
  if [[ ! -d "$_ds/$_apkg/trunk/" ]]; then
    for _ds in $_D_ABS; do
      pushd "$_ds/"
      _msg "Invoking 'svn update $_apkg' in $_ds/"
      svn update "$_apkg"
      # After invoking `svn update` we need to check if the directory
      # for our package `$_apkg` does exist.
      [[ ! -d "$_ds/$_apkg/trunk" ]] || { popd; break; }
      popd
    done
  fi

  # We scan all ABS sources again to see if there is `$_apkg`
  for _ds in $_D_ABS; do
    [[ ! -d "$_ds/$_apkg/trunk/" ]] || break
  done

  _ds="$_ds/$_apkg/trunk/"

  # If we don't find it at all, return with error
  [[ -d "$_ds/" ]] \
  || { _err "Directory not found  $_ds"; return 1; }

  # We nee to be on the master before creating new branch
  git co master \
  && git co -b "$_pkg" "TheSmallBang" \
  || {
    _err "Failed to switch to 'master' or to create new branch $_pkg"
    return 1
  }

  cp -r "$_ds/" "$_dd/"

  # Generate the README.md
  _f_readme="$_dd/README.md"
  [[ -f "$_f_readme" ]] \
  || {
    pushd "$PWD"

    cd "$_ds/" \
    && {
      # Test if svn return any error
      svn info >/dev/null 2>&1 \
      || {
        _err "svn info failed to run in $_ds"
        popd; return 1
      }

      svn update >/dev/null 2>&1 \
      || {
        _err "svn update failed to run in $_ds"
        popd; return 1
      }

      # Get the revision information
      _rev="$(svn info | grep ^Revision: | head -1 | awk '{print $NF}')"

      # README contents
      {
        echo "Import from ArchLinux's ABS package '$_apkg'"
        echo ""
        svn info \
          | grep -E "^(URL|Revision):"
      } \
        > "$_f_readme"
    }

    popd
  }

  # Generate git commit. Please note that the commit messge contains
  # the revision number that will be used in the future.
  # FIXME: This commit message is not perfect. Because the revision
  # FIXME: number is not correctly true. We need also use the repo-
  # FIXME: sitory name, e.g, core/extra/packages. This full information
  # FIXME: should contain in the README.md file.
  git add "$_dd" \
  && git commit "$_pkg/" -m"$_pkg: Import from ABS $_apkg @ $_rev" \
  && git co master \
  && _fix_the_1st_tag_on_package_branch "$_pkg" \
  || { _err "Something wrong with git repository"; return 1; }
}

# Date   : 2013 Nov 04th
# Purpose: Add missing README.md due to a bug
#         See _utils , commit b72c4cba9454285c17e409d96c119e387f1f56e8
# Usage  : This function accepts only one parameter (a package name)
#
_import_package_add_missing_readme() {
  local _pkg="${1-}"
  local _ds=""
  local _D_ABS="${ABS:-$PWD/a/ $PWD/b/}"
  local _f_readme=""
  local _svn_uri=""
  local _svn_rev=""

  [[ -n "${1-}" ]] || return 0

  git checkout "$_pkg" >/dev/null 2>&1 || return 1
  git show "$_pkg/README.md" >/dev/null 2>&1 && return 0
  _msg "Adding missing README.md for '$_pkg' package"

  # We scan all ABS sources again to see if there is `$_apkg`
  for _ds in $_D_ABS; do
    [[ ! -d "$_ds/$_pkg/trunk/" ]] || break
  done

  if [[ ! -d "$_ds/$_pkg/trunk/" ]]; then
    _err "Unable to find source tree '$_ds/$_pkg/trunk/'"
    return 1
  fi

  _f_readme="$PWD/$_pkg/README.md"
  pushd "$PWD" >/dev/null
  cd "$_ds/$_pkg/trunk" \
  && {
    _svn_uri="$(svn info | grep -E "^URL:")"
  }
  popd >/dev/null

  [[ -n "$_svn_uri" ]] \
  || {
    _err "Unable to get URI information from svn tree '$_ds/$_pkg/trunk'"
    return 1
  }

  _svn_rev="$( \
      git log --format="%H %s" -- \
      | grep "Import from ABS $_pkg @ " \
      | awk '{print $NF}' ; \
      _is_good_pipe ; \
    )" \
  || {
    _err "Unable to detect import information from git log"
    return 1
  }

  _msg "README.md contents saved in '$_f_readme'"
  {
    echo "Import from ArchLinux's ABS package '$_pkg'"
    echo ""
    echo "$_svn_uri"
    echo "Revision: $_svn_rev"
  } \
    > "$_f_readme"
  git add "$_pkg/README.md"
  git ci -am'Add README.md (See b72c4cba9454285c17e409d96c119e387f1f56e8)'
}


# Import all packages provided in the arguments
_import_packages() {
  while (( $# )); do
    _import_package $1
    shift
  done
}

# Check if there is a tag that indicates time when package is imported
# from the ABS. This first tag is important bc it helps `_makepkg`.
#
# Strategy
#
#   1. Check if the branch is a package branch: the name of the branch
#      <branch> shoud lead to the file <branch>:<branch>/PKGBUILD
#   2. Find the first commit of the <branch>
#   3. Check if there is tag at the commit
#      1. If there is tag, but it isn't an annotation tag -> fix it
#      2. If there is not a tag
#         1. Find the version from PKGBUILD
#         2. Create new annotatag from that version
#
# Input
#   $1 => The branch to check (this should be a package branch)
#
_fix_the_1st_tag_on_package_branch() {
  local _br="${1:-HEAD}"
  local _commit=
  local _tag=
  local _pkgver=

  _br="$(_get_git_branch "$_br")" || return 1
  git show "$_br:$_br/PKGBUILD" >/dev/null \
  || {
    _err "The branch '$_br' is not a package branch"
    return 1
  }
  _commit="$( \
      git log --pretty="format:%H" "TheSmallBang".."$_br" -- | tail -1 ;\
      _is_good_pipe ; \
    )" \
  || return 1

  # Because the file `PKGBUILD` does exist in the branch, there is
  # no way that `_commit` is empty (as `TheSmallBang` and our branch
  # have a the same current commit.

  if _tag="$(git describe --tags --exact-match "$_commit" 2>/dev/null)"; then
    _tag="$(_get_package_name_from_tag "$_tag")" || return 1
    [[ "$_tag" != "$_br" ]] || return 0
    _err "Tag was created but it doesn't match package branch '$_br'"
    return 1
  fi

  _pkgver="$(
      git show "$_commit":$_br/PKGBUILD \
        | _get_version_from_old_PKGBUILD ; \
      _is_good_pipe ; \
    )" \
  || return 1

  git tag -s -a \
    -m"The original source from the ABS" \
    "$_br-$_pkgver" "$_commit"
}

# Return version number from the old PKGBUILD. This is useful when
# importing the old package to our build system: immediately after
# importing we will need the version number to create the first tag.
#
# Note: If the version string has only one number, it will be ignored.
#
# Input
#   $1 => STDIN (contents of an ArchLinux PKGBUILD)
#
_get_version_from_old_PKGBUILD() {
  awk '
    BEGIN {
      tmp = sprintf("%c", 39);
      reg1 = sprintf("^pkgver%s([0-9]+(\\.[0-9]+){1,3})%s[[:space:]]*$", tmp, tmp);
      tmp = "";
    }
    {
      if (match($0, reg1, m)) {
        tmp = m[1];
      }
      else if (match($0, /^pkgver="([0-9]+(\.[0-9]+){1,3})"[[:space:]]*$/, m)) {
        tmp = m[1];
      }
      else if (match($0, /^pkgver=([0-9]+(\.[0-9]+){1,3})[[:space:]]*$/, m)) {
        tmp = m[1];
      }
    }
    END {
      if (tmp == "") {
        printf(":: Error:: Unable to read \"pkgver\" from PKGBUILD\n") > "/dev/stderr";
        exit(1);
      }
      else {
        printf("%s\n", tmp);
      }
    }
    '
}
