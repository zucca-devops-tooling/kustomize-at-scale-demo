#!/bin/bash

# --- Configuration ---
NUM_APPS=${1:-50}
RESOURCES_PER_APP=${2:-30}
OUTPUT_DIR="advanced-workload"

# --- Wordlists for realistic names ---
ENVS=("prod" "staging" "dev" "qa")
SERVICES=("database" "cache" "api" "frontend" "worker" "auth" "storage" "mq")
TYPES=("main" "replica" "canary" "blue" "green" "backup" "archive" "temp")
# A long repeating string to make regex matching difficult
REPEATING_PATTERN="backup-job-backup-job-backup-job-backup-job"

echo "Generating advanced workload..."
echo "  - Number of Apps: ${NUM_APPS}"
echo "  - Resources per App: ${RESOURCES_PER_APP}"
echo "  - Output Directory: ${OUTPUT_DIR}"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

for i in $(seq 1 $NUM_APPS); do
  APP_DIR="${OUTPUT_DIR}/app-${i}"
  mkdir -p "${APP_DIR}"

  # Create the kustomization file for this app
  KUSTOMIZATION_FILE="${APP_DIR}/kustomization.yaml"
  echo "apiVersion: kustomize.config.k8s.io/v1beta1" > "${KUSTOMIZATION_FILE}"
  echo "kind: Kustomization" >> "${KUSTOMIZATION_FILE}"
  echo "resources:" >> "${KUSTOMIZATION_FILE}"

  for j in $(seq 1 $RESOURCES_PER_APP); do
    RESOURCE_FILE="resource-${j}.yaml"
    echo "  - ${RESOURCE_FILE}" >> "${KUSTOMIZATION_FILE}"

    # Generate a random, realistic name
    RAND_ENV=${ENVS[$RANDOM % ${#ENVS[@]}]}
    RAND_SVC=${SERVICES[$RANDOM % ${#SERVICES[@]}]}
    RAND_TYPE=${TYPES[$RANDOM % ${#TYPES[@]}]}
    RAND_HASH=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)

    # Every 10th resource will get the special "expensive" name
    if (( j % 10 == 0 )); then
        RESOURCE_NAME="${RAND_ENV}-${REPEATING_PATTERN}-${RAND_HASH}"
    else
        RESOURCE_NAME="${RAND_ENV}-${RAND_SVC}-${RAND_TYPE}-${RAND_HASH}"
    fi

    # Create the resource file
    cat > "${APP_DIR}/${RESOURCE_FILE}" <<EOL
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${RESOURCE_NAME}
data:
  app: "app-${i}"
  resource: "resource-${j}"
EOL
  done
done

echo "Generation complete."