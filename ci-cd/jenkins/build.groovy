def call() {

    stage('Build Docker Images') {

        echo 'Building Docker images...'

        sh '''
            docker build -t gateway-service ./services/gateway
            docker build -t auth-service ./services/auth
            docker build -t converter-service ./services/converter
            docker build -t notification-service ./services/notification
        '''

        echo 'Docker images built successfully.'
    }
}