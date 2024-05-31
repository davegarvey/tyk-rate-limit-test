#!/bin/bash

readonly DASHBOARD_BASE_URL="$(jq -r '.tyk.dashboard.host' config.json)"
readonly DASHBOARD_API_TOKEN="$(jq -r '.tyk.dashboard.token' config.json)"
readonly GATEWAY_BASE_URL="$(jq -r '.tyk.gateway.host' config.json)"
readonly GATEWAY_API_TOKEN="$(jq -r '.tyk.gateway.token' config.json)"
readonly TEST_SUMMARY_PATH="output/rl-test-output-summary.csv"
readonly TEST_DETAIL_PATH="output/rl-test-output-detail.csv"
export_analytics=false
show_detail=false

while getopts "de" opt; do
  case ${opt} in
    d ) 
        show_detail=true
        echo "Detailed analytics will be displayed"
      ;;
    e ) 
        export_analytics=true
        echo "Analytics data will be exported"
      ;;
    \? ) 
        echo "Invalid option: -$OPTARG" 1>&2
        exit 1
      ;;
  esac
done

shift $((OPTIND -1))
test_plans_to_run=("$@")

if [ ${#test_plans_to_run[@]} -eq 0 ]; then
  echo "No tests to run. Provide test plan names as arguments. e.g. ./test.sh tp001"
  exit 0
fi

generate_requests() {
    local clients="$1"
    local requests_per_second="$2"
    local requests_total="$3"
    local target_url="$4"
    local api_key="$5"
    echo -e "\nclients: $clients\nrequests_per_second: $requests_per_second\nrequests_total: $requests_total\napi_key: $api_key\ntarget_url: $target_url\n"
    hey -c "$clients" -q "$requests_per_second" -n "$requests_total" -H "Authorization: $api_key" "$target_url" #1> /dev/null
}

create_api() {
  api_data_path="$1"
  response=$(curl -s -H "Authorization:$DASHBOARD_API_TOKEN" $DASHBOARD_BASE_URL/api/apis -d @$api_data_path)
  status=$(echo "$response" | jq -r '.Status')
  if [ "$status" != "OK" ]; then
    echo "\nERROR: API creation failed"
    echo "$response"
    exit 1
  else
    imported_api_id=$(echo "$response" | jq -r '.Meta')
    api_listen_path=$(jq -r '.api_definition.proxy.listen_path' "$api_data_path")
    # wait for API to become available on the gateway before returning
    while [ "$(curl -o /dev/null -s -w "%{http_code}" -H "x-tyk-authorization: $GATEWAY_API_TOKEN" $GATEWAY_BASE_URL$api_listen_path)" == "404" ]; do
      sleep 1
    done 
  fi 
}

delete_api() {
  api_id="$1"
  response=$(curl -s -H "Authorization:$DASHBOARD_API_TOKEN" --request DELETE $DASHBOARD_BASE_URL/api/apis/$api_id)
  status=$(echo "$response" | jq -r '.Status')

  if [ "$status" != "OK" ]; then
    echo -e "\nERROR: key deletion failed"
    echo "$response"
    exit 1
  fi 
}

create_key() {
  key_data_path="$1"
  response=$(curl -s -H "x-tyk-authorization:$GATEWAY_API_TOKEN" $GATEWAY_BASE_URL/tyk/keys -d @$key_data_path)
  status=$(echo "$response" | jq -r '.status')

  if [ "$status" != "ok" ]; then
    echo -e "\nERROR: key creation failed"
    echo "$response"
    exit 1
  else
    # return key
    echo $(echo "$response" | jq -r '.key')
  fi 
}

delete_key() {
  key="$1"
  response=$(curl -s -H "x-tyk-authorization:$GATEWAY_API_TOKEN" --request DELETE $GATEWAY_BASE_URL/tyk/keys/$key)
  status=$(echo "$response" | jq -r '.status')

  if [ "$status" != "ok" ]; then
    echo -e "\nERROR: key deletion failed"
    echo "$response"
    exit 1
  fi 
}

read_key() {
  key="$1"
  response=$(curl -s -H "x-tyk-authorization:$GATEWAY_API_TOKEN" $GATEWAY_BASE_URL/tyk/keys/$key)
  echo "res: $response"
  # status=$(echo "$response" | jq -r '.status')

  # if [ "$status" != "ok" ]; then
  #   echo -e "\nERROR: key deletion failed"
  #   echo "$response"
  #   exit 1
  # fi 
}

get_analytics_data() {
    local from_epoch="$1"
    local request_count="$2"
    local analytics_url="$DASHBOARD_BASE_URL/api/logs/?start=$from_epoch&p=-1"
    local data=""
    local analytics_count=0

    while [ "$analytics_count" -ne "$request_count" ]; do
        data=$(curl -s -H "Authorization: $DASHBOARD_API_TOKEN" $analytics_url)
        analytics_count=$(jq '.data | length' <<< "$data")
        
        # check that there is equivalent amount of analytics records to API requests sent
        if [ "$analytics_count" -ne "$request_count" ]; then
            # pause, to allow time for analytics data to be processed
            sleep 1
        fi
    done

    echo "$data"
}

# clear the test output files
> $TEST_SUMMARY_PATH
> $TEST_DETAIL_PATH
test_plan_run=false

for test_plan in "${test_plans_to_run[@]}"; do
    test_plan_path="test-plans/$test_plan.json"
    test_plan_file_name=$(basename "${test_plan_path%.*}")

    if [ ! -e "$test_plan_path" ]; then
        echo "Test plan $test_plan_path does not exist"
        continue
    fi

    echo -e "\nRunning test plan \"$test_plan_file_name\""
    test_plan_run=true
    target_url=$(jq -r '.target.url' $test_plan_path)
    target_authorization=$(jq -r '.target.authorization' $test_plan_path)
    load_clients=$(jq '.target.load.clients' $test_plan_path)
    load_rate=$(jq '.target.load.rate' $test_plan_path)
    load_total=$(jq '.target.load.total' $test_plan_path)

    
    imported_api_id=""
    imported_key=""
    if jq -e 'has("import")' "$test_plan_path" >/dev/null 2>&1; then
      if jq -e '.import | has("api")' "$test_plan_path" >/dev/null 2>&1; then
        api_data_path=$(jq -r '.import.api' "$test_plan_path")
        echo "Creating API \"$(jq -r '.api_definition.name' "$api_data_path")\""
        create_api $api_data_path
      fi
      if jq -e '.import | has("key")' "$test_plan_path" >/dev/null 2>&1; then
        key_data_path=$(jq -r '.import.key' "$test_plan_path")
        echo -n "Creating Key"
        imported_key=$(create_key $key_data_path)
        echo " $imported_key"
        if [ "$target_authorization" != "" ]; then
          echo "WARNING: Created key overrides key defined in test plan. Set test plan 'authorization' value to an empty string to prevet this warning."
        fi
      fi
    fi

    # test_data_source=$(jq -r '.dataSource' $test_plan_path)
    key_file_path=$(jq -r '.import.key' $test_plan_path)
    api_file_path=$(jq -r '.import.api' $test_plan_path)
    # TODO: This approach 'first' is a hack to deal with keys that have multiple authz configs.
    # It needs to be updates to get the correct authz config for the api that is to be tested against.
    # It only happens to work here because the first rate limit is the same as the API to be tested against.
    key_rate=$(jq 'first(.access_rights[] | .limit.rate)' $key_file_path)
    key_rate_period=$(jq 'first(.access_rights[] | .limit.per)' $key_file_path)
    analytics_data=""


    echo "Generating $load_total requests @ ${load_rate}rps at $target_url"

    # wait 2 seconds to ensure there is a reasonable gap between the batches of analytics records generated by different test plans
    sleep 2

    current_time=$(date +%s)
    generate_requests $load_clients $load_rate $load_total $target_url $target_authorization
    

    echo "Reading analytics data"
    analytics_data=$(get_analytics_data $current_time $load_total)

    echo "Parsing analytics data"
    parsed_data_file_path="output/rl-parsed-data-$test_plan_file_name.csv"
    jq -r '.data[] | [.ResponseCode, .TimeStamp] | join(" ")' <<< "$analytics_data" > $parsed_data_file_path

    echo "Analysing data"
    awk -v test_plan_file_name="$test_plan_file_name" \
        -v rate_limit="$key_rate" \
        -v rate_limit_period="$key_rate_period" \
        -v summary_data_path="$TEST_SUMMARY_PATH" \
        -f templates/rl-analysis-template.awk $parsed_data_file_path >> $TEST_DETAIL_PATH

    if [ "$export_analytics" == "true" ]; then
        echo "Exporting analytics data"
        echo "$analytics_data" > .context-data/rl-test-analytics-export-$test_plan_file_name.json
    fi

    # data cleanup
    if [ "$imported_api_id" != "" ]; then
      echo "Deleting API"
      delete_api $imported_api_id
    fi
    if [ "$imported_key" != "" ]; then
      echo "Deleting key"
      delete_key $imported_key
    fi
done

if [ "$test_plan_run" = "true" ]; then
    echo -e "\nTest plans complete"

    if [ "$show_detail" = "true" ]; then
        echo -e "\nDetailed Rate Limit Analysis"
        awk -f templates/test-output-detail-template.awk $TEST_DETAIL_PATH
    fi

    echo -e "\nSummary Results"
    awk -f templates/test-output-summary-template.awk $TEST_SUMMARY_PATH
else
  echo "No test plans were run"
fi
