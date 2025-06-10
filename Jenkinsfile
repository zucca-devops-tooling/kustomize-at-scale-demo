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
                                echo "❌ Failed to build ${appPath}, skipping..."
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
        stage('DEBUG: Find Failing Kyverno Resource File') {
            steps {
                script {
                    echo "Scanning for all resource files in '${builtAppsFolder}'..."

                    // Get the list of all the individual files to test.
                    // Using findFiles is the robust Jenkins way to do this.
                    def resourceFiles = findFiles(glob: "${builtAppsFolder}/**")

                    echo "Scan starting... This will test ${resourceFiles.length} individual files."

                    // Loop through every single file that kustomize generated.
                    for (def resourceFile in resourceFiles) {

                        echo "--- TESTING FILE: ${resourceFile.path} ---"

                        // Run kyverno apply on ONLY this single file and capture all output
                        def output = sh(
                            script: "kyverno apply ${policiesFile} --resource ${resourceFile.path} 2>&1 || true",
                            returnStdout: true
                        ).trim()

                        // Check if the output contains the specific error message we've been seeing.
                        if (output.contains("Policies Skipped")) {
                            def fileContent = readFile(resourceFile.path)

                            // Fail the build immediately with a clear, detailed error message
                            // that includes the filename and its exact content.
                            error("""
                                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                                FOUND FAILING RESOURCE!
                                The Kyverno CLI skipped policies when processing this file.

                                FILE NAME: ${resourceFile.path}

                                FILE CONTENT:
                                ---
                                ${fileContent}
                                ---

                                FULL KYVERNO OUTPUT FOR THIS RESOURCE:
                                ---
                                ${output}
                                ---
                                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                            """)
                        }
                    }

                    echo "Scan complete. No individual resource file caused policies to be skipped."
                }
            }
        }

        stage('Apply kyverno policies') {
            steps {
                script {
                    sh "kyverno apply ${policiesFile} --resource ${builtAppsFolder} --audit-warn > ${kyvernoResults} 2>&1"
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
