#!/bin/bash
echo "Generating resources for 5,000,000 operation test..."
rm -rf massive-test-resources-5M
mkdir massive-test-resources-5M

# Generate 100 files
for i in {1..100}
do
  # Define the output file for this batch
  FILE_PATH="kustomize-output/resources-part-${i}.yaml"
  echo "---" > $FILE_PATH

  # Generate 100 resources in each file
  for j in {1..50}
  do
    RESOURCE_NAME="test-cm-${i}-${j}"
    echo "apiVersion: v1" >> $FILE_PATH
    echo "kind: ConfigMap" >> $FILE_PATH
    echo "metadata:" >> $FILE_PATH
    echo "  name: ${RESOURCE_NAME}" >> $FILE_PATH
    echo "  annotations:" >> $FILE_PATH
    # THE CHANGE: Now generating 100 annotations per resource
    for k in {1..50}
    do
      echo "    stress-test.io/key-${k}: 'value-for-check-${k}-and-some-extra-data-to-make-it-longer-and-even-more-data-to-increase-size'" >> $FILE_PATH
    done
    echo "data:" >> $FILE_PATH
    echo "  some-data: 'hello'" >> $FILE_PATH
    echo "---" >> $FILE_PATH
  done
  echo "Generated ${FILE_PATH}"
done

echo "Generation complete."