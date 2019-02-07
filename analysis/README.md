# Analysis Tools

This directory contains tools useful for analyzing the behavior of CORD and
its components.

## multithread-save

This tool helps identify potential race conditions in XOS caused by the same field
being saved from multiple tasks, where a task is a sync step, event step, pull
step, or model policy.