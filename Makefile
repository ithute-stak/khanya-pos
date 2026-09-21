SHELL := /bin/bash

.PHONY: up down api-test api-lint mobile-get

up:
	cp -n .env.example .env || true
	docker compose up --build

down:
	docker compose down

api-test:
	cd services/api && python -m pytest

api-lint:
	cd services/api && python -m compileall app

mobile-get:
	cd apps/mobile && flutter pub get
