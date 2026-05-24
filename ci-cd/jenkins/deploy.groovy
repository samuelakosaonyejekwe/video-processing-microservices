def call() {

    stage('Deploy Application') {

        echo 'Deploying application to Kubernetes...'

        sh '''
            kubectl apply -f infrastructure/kubernetes/namespaces/

            kubectl apply -f infrastructure/kubernetes/gateway/

            kubectl apply -f infrastructure/kubernetes/auth/

            kubectl apply -f infrastructure/kubernetes/converter/

            kubectl apply -f infrastructure/kubernetes/notification/
        '''

        echo 'Deployment completed successfully.'
    }
}