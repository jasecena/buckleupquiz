# Common tasks. On Linux only the Swift package and content targets work;
# the iOS app needs macOS + Xcode.
.PHONY: help generate open test test-core test-core-docker test-content validate validate-strict test-app clean

SWIFT_IMAGE ?= swift:6.1-noble

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

generate: ## Generate BuckleUpQuiz.xcodeproj from project.yml (needs xcodegen)
	xcodegen generate

open: generate ## Generate and open in Xcode
	open BuckleUpQuiz.xcodeproj

test: test-content validate test-core ## Run every test that works on this machine

test-core: ## QuizCore tests with a local Swift toolchain
	swift test --package-path Packages/QuizCore

test-core-docker: ## QuizCore tests in Docker (no local Swift needed)
	docker run --rm --user "$$(id -u):$$(id -g)" -e HOME=/tmp -v "$(CURDIR)":/repo -w /repo \
		$(SWIFT_IMAGE) swift test --package-path Packages/QuizCore

test-content: ## Unit tests for the content validator
	python3 -m unittest discover -s scripts/tests

validate: ## Validate the question bank
	python3 scripts/validate_content.py

validate-strict: ## Validate and enforce launch content targets
	python3 scripts/validate_content.py --strict

test-app: generate ## Build and test the iOS app on a simulator (macOS)
	set -o pipefail && xcodebuild test -project BuckleUpQuiz.xcodeproj -scheme BuckleUpQuiz \
		-destination "$$(scripts/ci/simulator-destination.sh)" CODE_SIGNING_ALLOWED=NO | xcbeautify

clean: ## Remove generated project and build output
	rm -rf build Packages/QuizCore/.build BuckleUpQuiz.xcodeproj App/Info.plist
