.PHONY: test lint

# Minimal test suite: shell syntax check for installer
lint:
	bash -n install.sh

test: lint
