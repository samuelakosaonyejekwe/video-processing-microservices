build:
	bash scripts/publish-docker-images.sh

push:
	bash scripts/publish-docker-images.sh

deploy:
	bash scripts/deploy-eks.sh
	bash scripts/create-docker-registry-secret.sh
	bash scripts/deploy-services.sh
	bash scripts/verify-deployment.sh

helm:
	bash scripts/deploy-helm.sh

eks:
	bash scripts/deploy-eks.sh

monitoring:
	bash scripts/deploy-monitoring.sh

observability:
	bash scripts/deploy-observability.sh

destroy:
	bash scripts/destroy-cluster.sh

local:
	bash scripts/setup-local-dev.sh

cleanup:
	bash scripts/cleanup.sh

test:
	pytest tests/