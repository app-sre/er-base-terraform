CONTAINER_ENGINE ?= $(shell which podman >/dev/null 2>&1 && echo podman || echo docker)

.PHONY: test
test:
	# test binaries are installed
	terraform --version

	# test /tmp is empty
	[ -z "$(shell ls -A /tmp)" ]

	# test /tmp is writable
	touch /tmp/test && rm /tmp/test

	[ -f "entrypoint.sh" ]

.PHONY: build
build:
	$(CONTAINER_ENGINE) build -t er-base-terraform:test .
