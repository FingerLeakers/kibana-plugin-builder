.PHONY: build dev size tags tar test run ssh circle node push dockerfile

ORG=blacktop
NAME=kibana-plugin-builder
REPO=$(ORG)/$(NAME)
VERSION?=$(shell http https://raw.githubusercontent.com/maliceio/malice-kibana-plugin/master/package.json | jq -r '.version')
NODE_VERSION?=$(shell curl -s https://raw.githubusercontent.com/elastic/kibana/v$(VERSION)/.node-version)

dockerfile: ## Update Dockerfiles
	sed -i.bu 's/ARG VERSION=.*/ARG VERSION=$(VERSION)/' Dockerfile
	sed -i.bu 's/ARG NODE_VERSION=.*/ARG NODE_VERSION=$(NODE_VERSION)/' Dockerfile.node

node: ### Build docker base image
	docker build --build-arg NODE_VERSION=${NODE_VERSION} -f Dockerfile.node -t $(ORG)/$(NAME):node .

build: dockerfile node ## Build docker image
	docker build --build-arg VERSION=$(VERSION) -t $(ORG)/$(NAME):$(VERSION) .

dev: base ## Build docker dev image
	docker build --squash --build-arg NODE_VERSION=${NODE_VERSION} -f Dockerfile.dev -t $(ORG)/$(NAME):$(VERSION) .

size: tags ## Update docker image size in README.md
	sed -i.bu 's/docker%20image-.*-blue/docker%20image-$(shell docker images --format "{{.Size}}" $(ORG)/$(NAME):$(VERSION)| cut -d' ' -f1)-blue/' README.md
	sed -i.bu '/latest/ s/[0-9.]\{3,5\}GB/$(shell docker images --format "{{.Size}}" $(ORG)/$(NAME):$(VERSION))/' README.md
	sed -i.bu '/$(VERSION)/ s/[0-9.]\{3,5\}GB/$(shell docker images --format "{{.Size}}" $(ORG)/$(NAME):$(VERSION))/' README.md
	sed -i.bu '/node/ s/[0-9.]\{3,5\}MB/$(shell docker images --format "{{.Size}}" $(ORG)/$(NAME):node)/' README.md

tags: ## Show all docker image tags
	docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" $(ORG)/$(NAME)

run: stop ## Run kibana plugin env
	@echo "===> Starting kibana elasticsearch..."
	@docker run --init -d --name kplug -p 9200:9200 -p 5601:5601 $(ORG)/$(NAME):$(VERSION)

ssh: ## SSH into docker image
	@docker run --init -it --rm --entrypoint=sh $(ORG)/$(NAME):$(VERSION)

tar: ## Export tar of docker image
	@docker save $(ORG)/$(NAME):$(VERSION) -o $(NAME).tar

test: ## Test build plugin
	@echo "===> Starting kibana tests..."
	@docker run --init --rm -p 9200:9200 -p 5601:5601 $(ORG)/$(NAME):$(VERSION) npm run test:quick --force

push: build size ## Push docker image to docker registry
	@echo "===> Pushing $(ORG)/$(NAME):node to docker hub..."
	@docker push $(ORG)/$(NAME):node
	@echo "===> Pushing $(ORG)/$(NAME):$(VERSION) to docker hub..."
	@docker push $(ORG)/$(NAME):$(VERSION)

circle: ci-size ## Get docker image size from CircleCI
	@sed -i.bu 's/docker%20image-.*-blue/docker%20image-$(shell cat .circleci/SIZE)-blue/' README.md
	@echo "===> Image size is: $(shell cat .circleci/SIZE)"

ci-build:
	@echo "===> Getting CircleCI build number"
	@http https://circleci.com/api/v1.1/project/github/${REPO} | jq '.[0].build_num' > .circleci/build_num

ci-size: ci-build
	@echo "===> Getting image build size from CircleCI"
	@http "$(shell http https://circleci.com/api/v1.1/project/github/${REPO}/$(shell cat .circleci/build_num)/artifacts circle-token==${CIRCLE_TOKEN} | jq '.[].url')" > .circleci/SIZE

clean: ## Clean docker image and stop all running containers
	docker-clean stop
	docker rmi $(ORG)/$(NAME):$(VERSION) || true
	docker rmi $(ORG)/$(NAME):node || true
	rm -rf malice/build

stop: ## Kill running kibana-plugin docker containers
	@docker rm -f kplug || true

# Absolutely awesome: http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := push
