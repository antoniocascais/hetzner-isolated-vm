SHELL := /bin/bash
.DEFAULT_GOAL := help
EXTRA ?=

.PHONY: help install create configure allow-ip destroy

help:
	@echo "Targets:"
	@echo "  install     Install required Ansible collections"
	@echo "  create      Create the server + firewall (SSH from your current IP only)"
	@echo "  configure   Install Claude over SSH; re-assert firewall from current IP"
	@echo "  allow-ip    Re-detect your IP and update the firewall (run if your IP changed)"
	@echo "  destroy     Delete the server + firewall (prompts for confirmation)"

install:
	ansible-galaxy collection install -r ansible/collections/requirements.yml

create: install
	./scripts/create.sh $(EXTRA)

configure: install
	./scripts/configure.sh $(EXTRA)

allow-ip: install
	./scripts/allow-ip.sh $(EXTRA)

destroy:
	./scripts/destroy.sh $(EXTRA)
