pipeline {

    agent any

    options {

        timestamps()

        disableConcurrentBuilds()

        ansiColor('xterm')

        buildDiscarder(
            logRotator(
                numToKeepStr: '20',
                artifactNumToKeepStr: '10'
            )
        )
    }

    environment {

        /*
        ======================================================
        AWS / EKS CONFIGURATION
        ======================================================
        */

        AWS_REGION = "${env.AWS_REGION}"

        CLUSTER_NAME = "${env.EKS_CLUSTER_NAME}"

        K8S_NAMESPACE = "${env.K8S_NAMESPACE}"

        /*
        ======================================================
        DOCKER REGISTRY
        ======================================================
        */

        DOCKER_REGISTRY = "${env.DOCKER_REGISTRY}"

        /*
        ======================================================
        GITHUB REPOSITORY
        ======================================================
        */

        GIT_REPOSITORY = "${env.GIT_REPOSITORY}"

        GIT_BRANCH = "${env.GIT_BRANCH}"

        /*
        ======================================================
        APPLICATION ENVIRONMENT
        ======================================================
        */

        APP_ENV = "${env.APP_ENV}"

        /*
        ======================================================
        IMAGE TAGGING
        ======================================================
        */

        IMAGE_TAG = "${env.BUILD_NUMBER}"
    }

    stages {

        /*
        ======================================================
        CHECKOUT SOURCE CODE
        ======================================================
        */

        stage('Checkout Source Code') {

            steps {

                git(
                    branch: "${GIT_BRANCH}",
                    url: "${GIT_REPOSITORY}",
                    credentialsId: 'github-credentials'
                )
            }
        }

        /*
        ======================================================
        VALIDATE REQUIRED VARIABLES
        ======================================================
        */

        stage('Validate Environment Variables') {

            steps {

                sh '''
                    set -e

                    REQUIRED_VARS=(
                        AWS_REGION
                        CLUSTER_NAME
                        K8S_NAMESPACE
                        DOCKER_REGISTRY
                        GIT_REPOSITORY
                        GIT_BRANCH
                        APP_ENV
                    )

                    for VAR in "${REQUIRED_VARS[@]}"
                    do
                        if [ -z "${!VAR}" ]; then
                            echo "ERROR: $VAR is not set."
                            exit 1
                        fi
                    done

                    echo "All required environment variables are set."
                '''
            }
        }

        /*
        ======================================================
        DOCKER LOGIN
        ======================================================
        */

        stage('Docker Login') {

            steps {

                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-credentials',
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {
                    sh '''
                        echo "${DOCKER_PASSWORD}" | docker login \
                            --username "${DOCKER_USERNAME}" \
                            --password-stdin "${DOCKER_REGISTRY}"
                    '''
                }
            }
        }

        /*
        ======================================================
        BUILD IMAGES
        ======================================================
        */

        stage('Build Images') {

            steps {

                sh '''
                    docker compose build
                '''
            }
        }

        /*
        ======================================================
        RUN TESTS
        ======================================================
        */

        stage('Run Tests') {

            steps {

                sh '''
                    pytest tests/ \
                        --maxfail=1 \
                        --disable-warnings
                '''
            }
        }

        /*
        ======================================================
        PUSH IMAGES
        ======================================================
        */

        stage('Push Images') {

            steps {

                sh '''
                    chmod +x scripts/push-images.sh

                    export IMAGE_TAG=${IMAGE_TAG}

                    export DOCKER_REGISTRY=${DOCKER_REGISTRY}

                    bash scripts/push-images.sh
                '''
            }
        }

        /*
        ======================================================
        TERRAFORM APPLY
        ======================================================
        */

        stage('Terraform Apply') {

            steps {

                sh '''
                    chmod +x infrastructure/terraform/scripts/terraform-apply.sh

                    bash infrastructure/terraform/scripts/terraform-apply.sh
                '''
            }
        }

        /*
        ======================================================
        CONFIGURE KUBECTL
        ======================================================
        */

        stage('Configure kubectl') {

            steps {

                sh '''
                    chmod +x infrastructure/terraform/scripts/configure-kubectl.sh

                    bash infrastructure/terraform/scripts/configure-kubectl.sh
                '''
            }
        }

        /*
        ======================================================
        INSTALL AWS LOAD BALANCER CONTROLLER
        ======================================================
        */

        stage('Install AWS Load Balancer Controller') {

            steps {

                sh '''
                    chmod +x scripts/install-aws-load-balancer-controller.sh

                    bash scripts/install-aws-load-balancer-controller.sh
                '''
            }
        }

        /*
        ======================================================
        INSTALL EXTERNAL DNS
        ======================================================
        */

        stage('Install External DNS') {

            steps {

                sh '''
                    chmod +x scripts/install-external-dns.sh

                    bash scripts/install-external-dns.sh
                '''
            }
        }

        /*
        ======================================================
        VALIDATE KUBERNETES
        ======================================================
        */

        stage('Validate Kubernetes') {

            steps {

                sh '''
                    kubectl get nodes

                    kubectl get pods -A
                '''
            }
        }

        /*
        ======================================================
        VALIDATE METRICS SERVER
        ======================================================
        */

        stage('Validate Metrics Server') {

            steps {

                sh '''
                    chmod +x scripts/validate-metrics-server.sh

                    bash scripts/validate-metrics-server.sh
                '''
            }
        }

        /*
        ======================================================
        VERIFY EKS
        ======================================================
        */

        stage('Verify EKS') {

            steps {

                sh '''
                    chmod +x infrastructure/terraform/scripts/verify-eks.sh

                    bash infrastructure/terraform/scripts/verify-eks.sh
                '''
            }
        }

        /*
        ======================================================
        DEPLOY HELM CHARTS
        ======================================================
        */

        stage('Deploy Helm Charts') {

            steps {

                sh '''
                    chmod +x scripts/deploy-helm.sh

                    export IMAGE_TAG=${IMAGE_TAG}

                    export APP_ENV=${APP_ENV}

                    bash scripts/deploy-helm.sh
                '''
            }
        }

        /*
        ======================================================
        DEPLOY OBSERVABILITY
        ======================================================
        */

        stage('Deploy Observability') {

            steps {

                sh '''
                    chmod +x scripts/deploy-observability.sh

                    bash scripts/deploy-observability.sh
                '''
            }
        }

        /*
        ======================================================
        DEPLOY CLUSTER AUTOSCALER
        ======================================================
        */

        stage('Deploy Cluster Autoscaler') {

            steps {

                sh '''
                    chmod +x scripts/deploy-cluster-autoscaler.sh

                    bash scripts/deploy-cluster-autoscaler.sh
                '''
            }
        }

        /*
        ======================================================
        RUN STRESS TEST
        ======================================================
        */

        stage('Run Stress Test') {

            steps {

                sh '''
                    chmod +x scripts/stress-test-converter.sh

                    bash scripts/stress-test-converter.sh
                '''
            }
        }

        /*
        ======================================================
        GENERATE RABBITMQ LOAD
        ======================================================
        */

        stage('Generate RabbitMQ Load') {

            steps {

                sh '''
                    chmod +x scripts/generate-rabbitmq-load.sh

                    bash scripts/generate-rabbitmq-load.sh
                '''
            }
        }

        /*
        ======================================================
        DEPLOY KUBERNETES SERVICES
        ======================================================
        */

        stage('Deploy') {

            steps {

                sh '''
                    chmod +x scripts/deploy-eks.sh scripts/deploy-services.sh scripts/lib/env-aliases.sh

                    export IMAGE_TAG=${IMAGE_TAG}
                    export APP_ENV=${APP_ENV}
                    export EKS_CLUSTER_NAME=${CLUSTER_NAME}
                    export DEPLOY_ROLLOUT_TIMEOUT=120s
                    export WORKER_ROLLOUT_TIMEOUT=120s
                    export DEPLOY_TRACING_STACK=true
                    export DEPLOY_MTLS_STACK=true
                    export SYNC_RABBITMQ_DEFINITIONS=true

                    bash scripts/deploy-eks.sh

                    bash scripts/deploy-services.sh
                '''
            }
        }

        /*
        ======================================================
        VERIFY DEPLOYMENT
        ======================================================
        */

        stage('Verify Deployment') {

            steps {

                sh '''
                    export DEPLOY_ROLLOUT_TIMEOUT=120s
                    export WORKER_ROLLOUT_TIMEOUT=120s
                    chmod +x scripts/verify-deployment.sh scripts/validate-hpa.sh scripts/validate-keda.sh scripts/validate-queue-workers.sh scripts/validate-mtls.sh scripts/verify-production-health.sh scripts/lib/env-aliases.sh
                    bash scripts/verify-deployment.sh
                    bash scripts/validate-hpa.sh
                    bash scripts/validate-keda.sh
                    bash scripts/validate-queue-workers.sh
                    bash scripts/verify-production-health.sh
                '''
            }
        }

        /*
        =====================================================
        INTEGRATION TESTS
        =====================================================
        */

        stage('Integration Tests') {

            steps {

                sh '''
                    pytest tests/integration/
                '''
            }
        }

        /*
        =====================================================
        END TO END TESTS
        =====================================================
        */

        stage('E2E Tests') {

            steps {

                sh '''
                    pytest tests/e2e/
                '''
            }
        }

        /*
        =====================================================
        KUBERNETES TESTS
        =====================================================
        */

        stage('Kubernetes Tests') {

            steps {

                sh '''
                    pytest tests/kubernetes/
                '''
            }
        }

        /*
        =====================================================
        OBSERVABILITY TESTS
        =====================================================
        */

        stage('Observability Tests') {

            steps {

                sh '''
                    pytest tests/observability/
                '''
            }
        }

        /*
        =====================================================
        LOAD TESTING
        =====================================================
        */

        stage('Load Testing') {

            steps {

                sh '''
                    k6 run tests/load/load-test.js
                '''
            }
        }

        /*
        =====================================================
        DEPLOYMENT VERIFICATION
        =====================================================
        */

        stage('Deployment Verification') {

            steps {

                sh '''
                    kubectl get pods -n ${K8S_NAMESPACE}
                    bash scripts/validate-hpa.sh
                '''
            }
        }

        /*
        ======================================================
        ROLLBACK ON FAILURE
        ======================================================
        */

        stage('Rollback On Failure') {

            when {

                expression {
                    currentBuild.currentResult == 'FAILURE'
                }
            }

            steps {

                sh '''
                    for deployment in gateway-deployment gateway-worker auth-service converter-service converter-worker notification-deployment notification-worker frontend-deployment; do
                        kubectl rollout undo deployment/${deployment} \
                            -n ${K8S_NAMESPACE} || true
                    done
                '''
            }
        }
    }

    /*
    ==========================================================
    POST ACTIONS
    ==========================================================
    */

    post {

        always {

            cleanWs()
        }

        success {

            echo 'Deployment completed successfully.'
        }

        failure {

            echo 'Deployment failed.'

            sh '''
                kubectl get pods -A || true

                kubectl describe pods -A || true
            '''
        }
    }
}