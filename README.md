## Simple rules

The package `foobar` follows some simple rules

1. It has its own branch `foobar` (a `package branch`)
2. Its files are under the directory `/foobar/`
3. It should not be merged with any other `package branch`
4. It follows the latest guideline found on the branch `TheBigBang`

## How to patch

Assume that you want to modify the build process of the package `foobar`.
You will need to fork the repository `buildsystem`, check out the branch
`foobar` and from that branch you create your own `feature branch`.
The new branch's name should start with `p_` as below.

````
$ git clone /uri/of/the/repository/buildsystem
$ git checkout foobar
$ git checkout -b p_foobar-new-feature
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

## Stay hungry, stay up-to-date

In any case, please make sure that you are up-to-date with the origin
repository.
