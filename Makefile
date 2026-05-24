build:
	bash scripts/build-images.sh

push:
	bash scripts/push-images.sh

deploy:
	bash scripts/deploy-services.sh

helm:
	bash scripts/deploy-helm.sh

eks:
	bash scripts/deploy-eks.sh

monitoring:
	bash scripts/deploy-monitoring.sh

destroy:
	bash scripts/destroy-cluster.sh

local:
	bash scripts/setup-local-dev.sh

cleanup:
	bash scripts/cleanup.sh

test:
	pytest tests/