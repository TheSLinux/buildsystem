## Simple rules

The package `foobar` follows some simple rules

1. It has its own branch `foobar` (a `package branch`)
2. Its files are under the directory `/foobar/`
3. It should not be merged with any other `package branch`
4. It follows the latest guideline found on the branch `TheBigBang`

## Feature branch

If you want to add some features and/or to fix some issues of a package,
please fork and create your own `feature branch`. _(See below for examples)_.
The name of `feature branch` should start by `p_`, follow by the name of
the package per-se, and follow the `feature name`. For example

````
p_foobar@this-is-a-new-feature
p_foobar#this-is-abug-fix
````

Here you can see some special characters `@`, `#`. You can also use
`+`, `=` or `%`. This character will help `s-makepkg` _(see the branch
**_utils** of our build system)_ to quickly find the package name.
Technically details can be found in the documentation of the function
`_get_package_name` from the branch `_utils`.

## How to patch

Assume that you want to modify the build process of the package `foobar`.
You will need to fork the repository `buildsystem`, check out the branch
`foobar` and from that branch you create your own `feature branch`.
The new branch's name should start with `p_` as below.

````
$ git clone /uri/of/the/repository/buildsystem
$ git checkout foobar
$ git checkout -b p_foobar@new-feature
#
# do what ever you want, commit your changes and create your patch
#
$ git format-patch --stdout foobar..p_foobar-new-feature \
    > /path/to/foobar-new-feature.patch
````

You can send your patch file `foobar-new-feature.patch` to some list
(please check `git-send-email`).

If you are using `github`, thing is simple. You just need to push your
feature branch `p_foobar-new-feature` to your fork on `github`, then
create a pull request.

## How to patch package's source code

The above section helps you to patch the **build process** of a package.
Sometimes you also need to modify the package's source code that are not
in our build system (yes you can add source code to our build system,
but you **shouldn't** do that).

If the source code has its own repository (`git`, `svn`, `cvs`), then
the easiest way is to make a clone of the original source tree, modify
the cloned data and create new patch (by using `git format-patch` or
`svn diff`, bla bla.)

Sometimes forking and creating patch from a `svn` or `cvs` repository
are painful because you don't have write permission to the original
repository _(here you can see why `git` and other `dcvs` really make life
beautiful.)_ Don't panic. You just need to create a temporary `git` repo-
sitory that contains the original source code.

````
#
# First you need to download the source to your local disk
#
$ wget /uri/of/the/specific/version/of/the/package/foobar
#
# decompress the archive
#
$ cd foobar-<version>
$ git init
$ git add *
$ git commit -am'The original source code'
$ git checkout -b p_foobar@new-feature
#
# make changes, commits
#
$ git format-patch --stdout master > p_foobar-new-feature.patch
#
# Now the patch file is ready to be sent out
#
````

There is nothing tricky here. `Git` allows you to create a temporary
repository for your work. After your patch is submitted you can simply
forget that repository.

## Stay hungry, stay up-to-date

In any case, please make sure that you are up-to-date with the original
repository (aka upstream).
