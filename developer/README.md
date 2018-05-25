# Developer Tools

This directory contains a collections of scripts usefull for development.

## Tag and Push Docker images to a remote registry

`tag_and_push.sh` tags and pushes to a remote registry all the images present in the local docker registry.
Please use `bash tag_and_push.sh -h` to see instructions.

## Imagebuilder

Usage:

```shell
python imagebuilder.py -f ../../helm-charts/examples/filter-images.yaml -x
```

## Download the full CORD source tree and optionally apply Gerrit patchsets

The `bootstrap-repo.sh` script installs the `repo` tool, uses it to
download the CORD source tree, and optionally applies one or more
patchsets from Gerrit to the tree.  It may be useful when
bootstrapping a new environment for development or testing.

Usage:
```
bootstrap-repo.sh [-p <project:change/revision>]
```
