# Shortcuts for the scripts in Scripts/ and Tools/. `make help` lists them.
#
#   make run ARGS="--open youtube --remote"
#   make test FILTER=NetflixNavTests
#   make ctl ARGS="press down"

.DEFAULT_GOAL := help
.PHONY: help build app release run test logs ctl hud icon ubol clean

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-9s %s\n", $$1, $$2}'

build: ## Compile (debug), no app bundle
	swift build

app: ## Debug build of build/Lazybones.app
	Scripts/build.sh --debug

release: ## Release build of build/Lazybones.app
	Scripts/build.sh

run: ## Build and run windowed, log in this terminal (ARGS= launch options)
	Scripts/run.sh $(ARGS)

test: ## Run the tests (FILTER= a test class or method)
	swift test $(if $(FILTER),--filter $(FILTER))

logs: ## Follow the app's log (ARGS="-c page", or "10m" for the past)
	Scripts/logs.sh $(ARGS)

ctl: ## Send a command to the running app (ARGS="press down", "state"...)
	Scripts/ctl.sh $(ARGS)

hud: Tools/RemoteHUD/RemoteHUD ## Build and open the raw remote input window
	Tools/RemoteHUD/RemoteHUD

Tools/RemoteHUD/RemoteHUD: Tools/RemoteHUD/RemoteHUD.swift
	cd Tools/RemoteHUD && swiftc -O -parse-as-library RemoteHUD.swift -o RemoteHUD

icon: ## Redraw Resources/AppIcon.icns
	swift Scripts/make-icon.swift

ubol: ## Download the latest uBlock Origin Lite
	Scripts/fetch-ubol.sh

clean: ## Remove build products
	rm -rf .build build Tools/RemoteHUD/RemoteHUD
