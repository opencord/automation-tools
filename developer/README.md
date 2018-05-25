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
