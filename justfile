#!/usr/bin/env -S just --working-directory . --justfile

[private]
@default:
    just --list

bootstrap:
    bash scripts/tooling/bootstrap.sh

[group('app')]
generate:
    bash scripts/tooling/generate.sh

[group('app')]
build:
    bash scripts/tooling/build.sh

[group('app')]
run:
    bash scripts/tooling/run.sh

[group('app')]
test-app:
    bash scripts/tooling/test_app.sh

[group('app')]
install-browser-bridge EXTENSION_ID='':
    extension_id="{{EXTENSION_ID}}"; extension_id="${extension_id#EXTENSION_ID=}"; bash scripts/tooling/install_browser_bridge.sh --extension-id "$extension_id"

[group('web')]
web-serve PORT='8000':
    port="{{PORT}}"; port="${port#PORT=}"; cd web && uv run python -m http.server "$port"

[group('web')]
web-check:
    mise exec -- prettier --check "web/**/*.{html,css}"
    uv run python -m scripts.web.validate_static_site web

[group('web')]
web-fmt:
    mise exec -- prettier --write "web/**/*.{html,css}"

[group('web')]
web-build: web-check
    rm -rf .build/web
    mkdir -p .build/web
    cp -R web/. .build/web/

[group('web')]
web-package VERSION='local': web-build
    version="{{VERSION}}"; version="${version#VERSION=}"; uv run python -m scripts.web.package_static_site --version "$version"

[group('maintenance')]
clean-build:
    rm -rf .build .DerivedData app/Shorty.xcworkspace app/build

[group('maintenance')]
clean-generated: clean-build
    rm -rf .venv .ruff_cache .rumdl_cache .pytest_cache .cache .mise .config .state
    find . -type d -name '__pycache__' -prune -exec rm -rf {} +

[group('maintenance')]
clean: clean-generated

test-python:
    uv run pytest tests -v

test: test-app test-python

lint: web-check
    bash scripts/tooling/lint.sh

fmt: web-fmt
    bash scripts/tooling/fmt.sh

ci-lint: lint

ci-python: test-python

ci-build:
    bash scripts/tooling/ci_build.sh

ci: ci-lint ci-python test-app web-build ci-build
