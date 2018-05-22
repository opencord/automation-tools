# Developer Tools

This directory contains a collections of scripts usefull for development.

## Tag and Push Docker images to a remote registry

The `tag_and_push.sh` script will read your local docker images starting with `xosproject`, tag and push them to a docker registry.
Please use `bash tag_and_push.sh -h` for usage instructions.

## Imagebuilder

Usage:

```
python imagebuilder.py -f ../../helm-charts/examples/filter-images.yaml -x
```