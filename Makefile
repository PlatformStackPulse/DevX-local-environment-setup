SHELL := /usr/bin/env bash

SHELLCHECK ?= shellcheck
SHFMT ?= shfmt

.PHONY: validate lint dry-run profiles compose

validate: lint dry-run profiles compose

lint:
	bash -n setup-ubuntu-wsl.sh
	bash -n setup-vscode-wsl.sh
	bash -n compose/localstack-init/init.sh
	$(SHELLCHECK) -S warning setup-ubuntu-wsl.sh setup-vscode-wsl.sh compose/localstack-init/init.sh
	$(SHFMT) -d -i 2 -ci setup-ubuntu-wsl.sh setup-vscode-wsl.sh compose/localstack-init/init.sh

dry-run:
	./setup-ubuntu-wsl.sh --dry-run
	./setup-vscode-wsl.sh --dry-run

profiles:
	@for profile in profiles/*.yaml; do \
		echo "Checking $$profile"; \
		grep -Eq '^name:' "$$profile"; \
		grep -Eq '^description:' "$$profile"; \
		grep -Eq '^status:' "$$profile"; \
	done

compose:
	@for file in compose/docker-compose.*.yaml; do \
		echo "Checking $$file"; \
		grep -Eq '^services:' "$$file"; \
	done
	@if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then \
		for file in compose/docker-compose.*.yaml; do \
			echo "Parsing $$file"; \
			docker compose -f "$$file" config >/dev/null; \
		done; \
	else \
		echo "Docker Compose not found; skipped Compose parse validation."; \
	fi
