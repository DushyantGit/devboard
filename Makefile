# DevBoard (advanced) — common tasks. Run `make` or `make help` to list them.
# These wrap the docker compose commands so learners don't have to memorise flags.

.DEFAULT_GOAL := help

# Host ports — keep in sync with .env (used by `make smoke`).
FRONTEND_PORT ?= 8080
BACKEND_PORT  ?= 8081

.PHONY: help setup up down logs ps reset smoke

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  make %-7s %s\n", $$1, $$2}'

setup: ## Create .env from .env.example if it does not exist yet
	@if [ ! -f .env ]; then cp .env.example .env && echo "created .env from .env.example"; else echo ".env already exists"; fi

up: setup ## Build and start the whole stack (frontend + backend + postgres)
	docker compose up --build

down: ## Stop and remove the containers
	docker compose down

logs: ## Tail logs from all services
	docker compose logs -f

ps: ## Show service status
	docker compose ps

reset: ## Wipe the database volume and rebuild (re-runs the init SQL + seed)
	docker compose down -v
	docker compose up --build

smoke: ## Check the running stack end-to-end (health, SPA, API → DB)
	@echo "-> backend health";   curl -fsS http://localhost:$(BACKEND_PORT)/health >/dev/null && echo "   OK backend healthy" || { echo "   FAIL backend"; exit 1; }
	@echo "-> frontend SPA";     curl -fsS http://localhost:$(FRONTEND_PORT)/ | grep -q '<title>' && echo "   OK frontend serving" || { echo "   FAIL frontend"; exit 1; }
	@echo "-> /api end-to-end";  curl -fsS "http://localhost:$(FRONTEND_PORT)/api/tasks?project_id=1" | grep -q '"tasks"' && echo "   OK api -> backend -> postgres" || { echo "   FAIL api"; exit 1; }
	@echo "all checks passed -> open http://localhost:$(FRONTEND_PORT)"
