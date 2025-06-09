def cliVersion = "1.0.1"
def cliFile = "kustomtrace-cli-${cliVersion}-all.jar"
def cliUrl = "https://github.com/zucca-devops-tooling/kustom-trace/releases/download/v${cliVersion}/${cliFile}"
def appListFile = "apps.yaml"
def builtAppsFolder = "kustomize-output"
def policiesFile = "policies.yaml"
def kyvernoResults = "results.yaml"

pipeline {
    agent any

    environment {
        GRADLE_OPTS = '-Dorg.gradle.jvmargs="-Xmx2g -XX:+HeapDumpOnOutOfMemoryError"'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Download kustom-trace-cli') {
            steps {
                script {
                    sh "curl -LO ${cliUrl}"
                }
            }
        }
        stage('Get apps to build') {
            steps {
                script {
                    sh "java -jar ${cliFile} -a ./kubernetes -o ${appListFile} list-root-apps"
                }
            }
        }
        stage('Build apps') {
            steps {
                script {
                    def apps = readYaml file: appListFile
                    sh "mkdir ${builtAppsFolder}"

                    if (apps && apps.'root-apps') {
                        apps.'root-apps'.each { appPath ->
                            def outputFile = builtAppsFolder + "/" + appPath.replaceAll("/", "_") + ".yaml"
                            echo "--- Executing build for: ${appPath} ---"
                            def buildResult = sh(
                                script: "kustomize build kubernetes/${appPath} -o ${outputFile}",
                                returnStatus: true
                            )

                            if (buildResult != 0) {
                                if (fileExists(outputFile)){
                                    echo "❌ Failed to build ${appPath}, skipping..."
                                    sh "rm -f ${outputFile}"
                                }
                            }
                        }
                    }
                }
            }
        }
        stage('Build kyverno policies') {
            steps {
                script {
                    sh "kustomize build ./policies -o ${policiesFile}"
                }
            }
        }
        stage('Apply kyverno policies') {
            steps {
                script {
                    sh "kyverno apply ${policiesFile} --resource ${builtAppsFolder} --audit-warn -v 3 > ${kyvernoResults} 2>&1"
                }
            }
            post {
                always {
                    script {
                        if (fileExists(kyvernoResults)) {
                            archiveArtifacts artifacts: "${kyvernoResults}"
                        }
                    }
                }
            }
        }
    }
    post {
        always {
            deleteDir()
        }
    }
}
