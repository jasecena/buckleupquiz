# Common tasks. On Linux only the Swift package and content targets work;
# the iOS app needs macOS + Xcode.
.PHONY: help generate open test test-core test-core-docker test-content validate validate-strict test-app clean \
	infra-bootstrap infra-domain infra-platform infra-plan infra-check

SWIFT_IMAGE ?= swift:6.1-noble

# AWS (ADR-0021). Pick the account with AWS_PROFILE=... ; state bucket is per account.
TF := terraform -chdir=infra/terraform
AWS_ACCOUNT = $(shell aws sts get-caller-identity --query Account --output text)
STATE_BUCKET = buckleupquiz-tfstate-$(AWS_ACCOUNT)
TF_INIT = init -input=false -reconfigure -backend-config=bucket=$(STATE_BUCKET)

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

infra-check: ## Check the AWS sign-in and the domain's availability
	@aws sts get-caller-identity --query Arn --output text
	@aws route53domains check-domain-availability --region us-east-1 --domain-name buckleupquiz.com \
		--query Availability --output text
	@aws route53domains list-prices --region us-east-1 --tld com \
		--query 'Prices[0].RegistrationPrice' --output text

infra-bootstrap: ## One-time: create the Terraform state bucket (state kept locally + copied to S3)
	@aws s3 cp s3://$(STATE_BUCKET)/bootstrap/terraform.tfstate infra/terraform/bootstrap/terraform.tfstate \
		2>/dev/null || true
	$(TF)/bootstrap init -input=false
	$(TF)/bootstrap apply
	aws s3 cp infra/terraform/bootstrap/terraform.tfstate s3://$(STATE_BUCKET)/bootstrap/terraform.tfstate

infra-domain: ## Register buckleupquiz.com, its DNS records and certificate (once; prevent_destroy)
	$(TF)/domain $(TF_INIT)
	$(TF)/domain apply

infra-platform: ## Content bucket, CloudFront and the error-report function
	$(TF)/platform $(TF_INIT)
	$(TF)/platform apply $(if $(NO_DOMAIN),-var use_custom_domain=false,)

infra-plan: ## Show pending changes in every stack
	$(TF)/domain $(TF_INIT) >/dev/null && $(TF)/domain plan
	$(TF)/platform $(TF_INIT) >/dev/null && $(TF)/platform plan
