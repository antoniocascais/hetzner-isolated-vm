SHELL := /bin/bash
.DEFAULT_GOAL := help
EXTRA ?=
VENV := .venv
PY := $(VENV)/bin/python

.PHONY: help install create configure allow-ip ssh destroy pause resume scan

help:
	@echo "Targets:"
	@echo "  install     Build .venv (pinned Python deps) + install Ansible collections"
	@echo "  create      Create the server + firewall + data volume (SSH from your current IP only)"
	@echo "  configure   Install Claude over SSH; mount the data volume; re-assert firewall from current IP"
	@echo "  allow-ip    Re-detect your IP and update the firewall (run if your IP changed)"
	@echo "  ssh         Resolve the box IP via API and SSH in"
	@echo "  destroy     Delete the server + firewall (prompts for confirmation); NEVER deletes the volume"
	@echo "  pause       Power off the server to stop compute billing; volume + firewall untouched"
	@echo "  resume      Power the server back on"
	@echo "  scan        Trivy scan (vuln + misconfig + secret) via trivy.yaml"

scan:
	trivy fs --config trivy.yaml .

install: $(VENV)/.installed

$(VENV)/.installed: requirements.txt ansible/collections/requirements.yml
	python3 -m venv $(VENV)
	$(PY) -m pip install --quiet --upgrade pip
	$(PY) -m pip install --quiet -r requirements.txt
	# -p + --force: galaxy treats the requirement as satisfied if ANY
	# configured path (e.g. the shared ~/.ansible/collections cache) already
	# has a matching version, and silently skips installing into ours. -p
	# pins the target dir; --force makes it actually copy there regardless
	# of what's already installed elsewhere, so this repo is reproducible
	# even on a machine with a pre-populated global cache.
	ANSIBLE_CONFIG=ansible/ansible.cfg $(VENV)/bin/ansible-galaxy collection install -r ansible/collections/requirements.yml -p ansible/collections --force
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

pause: install
	./scripts/pause.sh $(EXTRA)

resume: install
	./scripts/resume.sh $(EXTRA)
