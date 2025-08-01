#!/bin/bash

#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_NAME="$1"

echo "The Project Name = ${PROJECT_NAME}"

if [ -z "${HOP_LOCATION}" ]; then
  HOP_LOCATION=/opt/hop
fi

if [ -z "${SUREFIRE_REPORT}" ]; then
  SUREFIRE_REPORT="true"
fi

# Get kafka parameters
if [ -z "${BOOTSTRAP_SERVERS}" ]; then
  BOOTSTRAP_SERVERS=kafka:9092
fi

# Get database parameters
if [ -z "${POSTGRES_HOST}" ]; then
  POSTGRES_HOST=postgres
fi

if [ -z "${POSTGRES_DATABASE}" ]; then
  POSTGRES_DATABASE=hop_database
fi

if [ -z "${POSTGRES_PORT}" ]; then
  POSTGRES_PORT=5432
fi

if [ -z "${POSTGRES_USER}" ]; then
  POSTGRES_USER=hop_user
fi

if [ -z "${POSTGRES_PASSWORD}" ]; then
  POSTGRES_PASSWORD=hop_password
fi

if [ -z "${PROJECT_NAME}" ]; then
  PROJECT_NAME="*"
fi

#set global variables
SPACER="==========================================="

# Set up a temporary folder
export TMP_FOLDER=/tmp/hop-it-$$
rm -rf "${TMP_FOLDER}"
mkdir -p "${TMP_FOLDER}"

#cleanup Temp
export TMP_TESTCASES="${TMP_FOLDER}"/testcases.xml
rm -f "${TMP_TESTCASES}"

# Set up auditing
# Start with a new blank slate every time
# This means it's not needed to delete a project
#
export HOP_AUDIT_FOLDER="${TMP_FOLDER}"/audit
rm -rf "${HOP_AUDIT_FOLDER}"
mkdir -p "${HOP_AUDIT_FOLDER}"

# Store current HOP_CONFIG_FOLDER
TMP_CONFIG_FOLDER="${HOP_CONFIG_FOLDER}"

#Loop over project folders
for d in "${CURRENT_DIR}"/../${PROJECT_NAME}/; do
  #cleanup project testcases
  rm -f "${TMP_TESTCASES}"

  if [[ "$d" != *"scripts/" ]] && [[ "$d" != *"surefire-reports/" ]] && [[ "$d" != *"hopweb/" ]]; then

    # If there is a file called disabled.txt the project is disabled
    #
    if [ ! -f "$d/disabled.txt" ]; then

      #set test variables
      start_time=$SECONDS
      test_counter=0
      errors_counter=0
      skipped_counter=0
      failures_counter=0

      PROJECT_NAME=$(basename $d)

      echo ${SPACER}
      echo "Starting Tests in project: ${PROJECT_NAME}"
      echo ${SPACER}

      # Increment timer and set test start time
      test_counter=$((test_counter + 1))

      # Create New Project
      export HOP_CONFIG_FOLDER="$d"

      # Find main hwf files in the test sub-folder
      #
      # TODO: add hpl support when result is returned correctly
      #
      find $d -name 'main*.hwf' | sort | while read f; do

        #cleanup temp files
        rm -f /tmp/test_output
        rm -f /tmp/test_output_err

        #set file and test name
        hop_file="$(realpath $f)"
        test_name=$(basename $f)
        test_name=${test_name//'main_'/}
        test_name=${test_name//'main-'/}
        test_name=${test_name//'.hwf'/}

        #Starting Test
        echo ${SPACER}
        echo "Starting Test: $test_name"
        echo ${SPACER}

        #Start time test
        start_time_test=$SECONDS

        #Run Test
        $HOP_LOCATION/hop-run.sh \
          -r "local" \
          -e "dev" \
          -p POSTGRES_HOST=${POSTGRES_HOST} \
          -p POSTGRES_DATABASE=${POSTGRES_DATABASE} \
          -p POSTGRES_PORT=${POSTGRES_PORT} \
          -p POSTGRES_USER=${POSTGRES_USER} \
          -p POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
          -p BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS} \
          -f $hop_file > >(tee /tmp/test_output) 2> >(tee /tmp/test_output_err >&1)

        #Capture exit code
        exit_code=${PIPESTATUS[0]}

        #Test time duration
        test_duration=$((SECONDS - start_time_test))

        if (($exit_code >= 1)); then
          errors_counter=$((errors_counter + 1))
          failures_counter=$((failures_counter + 1))
          #Write single line to overview file
          echo $test_name >>"${CURRENT_DIR}"/../surefire-reports/failed_tests
          #Create surefire xml failure
          echo "<testcase name=\"$test_name\" time=\"$test_duration\">" >>${TMP_TESTCASES}
          echo "<failure type=\"$test_name\"></failure>" >>${TMP_TESTCASES}
          echo "<system-out>" >>${TMP_TESTCASES}
          echo "<![CDATA[" >>${TMP_TESTCASES}
          cat /tmp/test_output >>${TMP_TESTCASES}
          echo "]]>" >>${TMP_TESTCASES}
          echo "</system-out>" >>${TMP_TESTCASES}
          echo "<system-err>" >>${TMP_TESTCASES}
          echo "<![CDATA[" >>${TMP_TESTCASES}
          cat /tmp/test_output_err >>${TMP_TESTCASES}
          echo "]]>" >>${TMP_TESTCASES}
          echo "</system-err>" >>${TMP_TESTCASES}
          echo "</testcase>" >>${TMP_TESTCASES}

        else
          #Write single line to overview file
          echo $test_name >>"${CURRENT_DIR}"/../surefire-reports/passed_tests
          #Create surefire xml success
          echo "<testcase name=\"$test_name\" time=\"$test_duration\">" >>${TMP_TESTCASES}
          echo "<system-out>" >>${TMP_TESTCASES}
          echo "<![CDATA[" >>${TMP_TESTCASES}
          cat /tmp/test_output >>${TMP_TESTCASES}
          echo "]]>" >>${TMP_TESTCASES}
          echo "</system-out>" >>${TMP_TESTCASES}
          echo "</testcase>" >>${TMP_TESTCASES}
        fi

        #Print results to console
        echo ${SPACER}
        echo "Test Result"
        echo ${SPACER}
        echo "Test duration: $test_duration"
        echo "Test Exit Code: $exit_code"

      done

      total_duration=$((SECONDS - start_time))

      #create final report
      if [ "${SUREFIRE_REPORT}" = "true" ]; then

        echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" >"${CURRENT_DIR}"/../surefire-reports/surefile_${PROJECT_NAME}.xml
        echo "<testsuite xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:noNamespaceSchemaLocation=\"https://maven.apache.org/surefire/maven-surefire-plugin/xsd/surefire-test-report-3.0.xsd\" version=\"3.0\" name=\"${PROJECT_NAME}\" time=\"$total_duration\" tests=\"$test_counter\" errors=\"$errors_counter\" skipped=\"$skipped_counter\" failures=\"$failures_counter\">" >>"${CURRENT_DIR}"/../surefire-reports/surefile_${PROJECT_NAME}.xml
        cat ${TMP_TESTCASES} >>"${CURRENT_DIR}"/../surefire-reports/surefile_${PROJECT_NAME}.xml
        echo "</testsuite>" >>"${CURRENT_DIR}"/../surefire-reports/surefile_${PROJECT_NAME}.xml

      fi
    fi
  fi
done

# Cleanup config and audit folders
#
rm -rf "${HOP_AUDIT_FOLDER}"
rm -rf "${TMP_FOLDER}"

# Set back to old config folder
export HOP_CONFIG_FOLDER="${TMP_CONFIG_FOLDER}"
