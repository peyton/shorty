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
install-browser-bridge EXTENSION_ID='' BROWSERS='chrome':
    extension_id="{{EXTENSION_ID}}"; extension_id="${extension_id#EXTENSION_ID=}"; browsers="{{BROWSERS}}"; browsers="${browsers#BROWSERS=}"; bash scripts/tooling/install_browser_bridge.sh --extension-id "$extension_id" --browsers "$browsers"

[group('app')]
uninstall-browser-bridge BROWSERS='chrome':
    browsers="{{BROWSERS}}"; browsers="${browsers#BROWSERS=}"; bash scripts/tooling/install_browser_bridge.sh --uninstall --browsers "$browsers"

[group('release')]
release-preflight VERSION='local':
    version="{{VERSION}}"; version="${version#VERSION=}"; bash scripts/tooling/release_preflight.sh --version "$version"

[group('release')]
app-package VERSION='local' ARTIFACT_LABEL='':
    version="{{VERSION}}"; version="${version#VERSION=}"; artifact_label="{{ARTIFACT_LABEL}}"; artifact_label="${artifact_label#ARTIFACT_LABEL=}"; if [ -n "$artifact_label" ]; then bash scripts/tooling/app_package.sh --version "$version" --artifact-label "$artifact_label"; else bash scripts/tooling/app_package.sh --version "$version"; fi

[group('release')]
source-package VERSION='local':
    version="{{VERSION}}"; version="${version#VERSION=}"; bash scripts/tooling/source_package.sh --version "$version"

[group('release')]
app-notarize VERSION='local':
    version="{{VERSION}}"; version="${version#VERSION=}"; bash scripts/tooling/app_notarize.sh --version "$version"

[group('release')]
dmg-package VERSION='local':
    version="{{VERSION}}"; version="${version#VERSION=}"; bash scripts/tooling/dmg_package.sh --version "$version"

[group('release')]
release-verify VERSION='local' ARTIFACT_LABEL='':
    version="{{VERSION}}"; version="${version#VERSION=}"; artifact_label="{{ARTIFACT_LABEL}}"; artifact_label="${artifact_label#ARTIFACT_LABEL=}"; if [ -n "$artifact_label" ]; then bash scripts/tooling/release_verify.sh --version "$version" --artifact-label "$artifact_label"; else bash scripts/tooling/release_verify.sh --version "$version"; fi

[group('release')]
safari-extension-verify:
    bash scripts/tooling/safari_extension_verify.sh

[group('release')]
appcast-generate VERSION='local' DOWNLOAD_URL='':
    version="{{VERSION}}"; version="${version#VERSION=}"; download_url="{{DOWNLOAD_URL}}"; download_url="${download_url#DOWNLOAD_URL=}"; bash scripts/tooling/appcast_generate.sh --version "$version" --download-url "$download_url"

[group('release')]
app-store-build VERSION='' BUILD_NUMBER='1':
    version="{{VERSION}}"; version="${version#VERSION=}"; build_number="{{BUILD_NUMBER}}"; build_number="${build_number#BUILD_NUMBER=}"; if [ -n "$version" ]; then bash scripts/tooling/app_store_build.sh --version "$version" --build-number "$build_number"; else bash scripts/tooling/app_store_build.sh --build-number "$build_number"; fi

[group('release')]
app-store-validate VERSION='' BUILD_NUMBER='':
    version="{{VERSION}}"; version="${version#VERSION=}"; build_number="{{BUILD_NUMBER}}"; build_number="${build_number#BUILD_NUMBER=}"; if [ -n "$version" ] && [ -n "$build_number" ]; then bash scripts/tooling/app_store_validate.sh --version "$version" --build-number "$build_number"; elif [ -n "$version" ]; then bash scripts/tooling/app_store_validate.sh --version "$version"; elif [ -n "$build_number" ]; then bash scripts/tooling/app_store_validate.sh --build-number "$build_number"; else bash scripts/tooling/app_store_validate.sh; fi

[group('release')]
app-store-archive VERSION BUILD_NUMBER:
    version="{{VERSION}}"; version="${version#VERSION=}"; build_number="{{BUILD_NUMBER}}"; build_number="${build_number#BUILD_NUMBER=}"; bash scripts/tooling/app_store_archive.sh --version "$version" --build-number "$build_number"

[group('release')]
app-store-export-testflight VERSION BUILD_NUMBER:
    version="{{VERSION}}"; version="${version#VERSION=}"; build_number="{{BUILD_NUMBER}}"; build_number="${build_number#BUILD_NUMBER=}"; bash scripts/tooling/app_store_export_testflight.sh --version "$version" --build-number "$build_number"

[group('release')]
profile-energy PROFILE='idle':
    profile="{{PROFILE}}"; profile="${profile#PROFILE=}"; bash scripts/tooling/energy_profile.sh "$profile"

[group('release')]
release VERSION='local' LANE='developer-id-with-safari' BUILD_NUMBER='1':
    version="{{VERSION}}"; version="${version#VERSION=}"; lane="{{LANE}}"; lane="${lane#LANE=}"; build_number="{{BUILD_NUMBER}}"; build_number="${build_number#BUILD_NUMBER=}"; bash scripts/tooling/release_lane.sh --version "$version" --lane "$lane" --build-number "$build_number"

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
marketing-screenshots:
    bash scripts/tooling/marketing_screenshots.sh

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

integration:
    uv run python -m scripts.tooling.macos_integration

test: test-app test-python integration

lint: web-check
    bash scripts/tooling/lint.sh

fmt: web-fmt
    bash scripts/tooling/fmt.sh

ci-lint: lint

ci-python: test-python

ci-build:
    bash scripts/tooling/ci_build.sh

ci: ci-lint ci-python test-app integration web-build ci-build
