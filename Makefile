SHELL := /bin/bash
.DEFAULT_GOAL := help
EXTRA ?=
VENV := .venv
PY := $(VENV)/bin/python

.PHONY: help install create configure allow-ip ssh destroy scan

help:
	@echo "Targets:"
	@echo "  install     Build .venv (pinned Python deps) + install Ansible collections"
	@echo "  create      Create the server + firewall (SSH from your current IP only)"
	@echo "  configure   Install Claude over SSH; re-assert firewall from current IP"
	@echo "  allow-ip    Re-detect your IP and update the firewall (run if your IP changed)"
	@echo "  ssh         Resolve the box IP via API and SSH in"
	@echo "  destroy     Delete the server + firewall (prompts for confirmation)"
	@echo "  scan        Trivy scan (vuln + misconfig + secret) via trivy.yaml"

scan:
	trivy fs --config trivy.yaml .

install: $(VENV)/.installed

$(VENV)/.installed: requirements.txt ansible/collections/requirements.yml
	python3 -m venv $(VENV)
	$(PY) -m pip install --quiet --upgrade pip
	$(PY) -m pip install --quiet -r requirements.txt
	$(VENV)/bin/ansible-galaxy collection install -r ansible/collections/requirements.yml
	@touch $@

create: install
	./scripts/create.sh $(EXTRA)

configure: install
	./scripts/configure.sh $(EXTRA)

allow-ip: install
	./scripts/allow-ip.sh $(EXTRA)

ssh: install
	./scripts/ssh.sh $(EXTRA)

destroy: install
	./scripts/destroy.sh $(EXTRA)
