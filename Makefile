.PHONY: check test-static test-e2e test-alpine release-check deploy-docs help

help:
	@echo "why666 CI/CD & Local Quality Commands:"
	@echo "  make check          Run fast static checks (bash -n, shellcheck, docs JS, version & contract sync)"
	@echo "  make test-e2e       Run full Linux end-to-end regression suite (requires Linux root)"
	@echo "  make test-alpine    Run Alpine BusyBox/OpenRC compatibility test in Docker"
	@echo "  make release-check  Dry-run release packaging & tarball integrity check"
	@echo "  make deploy-docs    Validate docs and deploy to Cloudflare Pages (whycat666)"

check: test-static

test-static:
	bash tests/static_check.sh

test-e2e:
	sudo bash tests/e2e_linux.sh

test-alpine:
	docker run --rm -v "$$(pwd)":/workspace -w /workspace alpine:3.20 sh -c "apk add --no-cache bash openrc curl jq ca-certificates >/dev/null && bash tests/e2e_alpine.sh"

release-check:
	bash tests/release_verify.sh --dry-run

deploy-docs: test-static
	npx --yes wrangler pages deploy docs --project-name=whycat666 --branch=main --commit-dirty=true
	@echo "Verifying live https://whycat666.pages.dev/ ..."
	@sleep 3
	@curl -fsSL "https://whycat666.pages.dev/?_v=$$(date +%s)" | grep -q 'https://github.com/whypuss/why666'
	@curl -fsSL "https://whycat666.pages.dev/?_v=$$(date +%s)" | grep -q 'yy ai json'
	@echo "LIVE DOCS VERIFIED OK"
