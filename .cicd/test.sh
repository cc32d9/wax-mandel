#!/bin/bash
set -eo pipefail
# variables
. ./.cicd/helpers/general.sh
# tests
if [[ $(uname) == 'Darwin' ]]; then # macOS
    export PATH=$PATH:~/mongodb/bin
    set +e # defer error handling to end
    TEST_COMMAND="\"./$1\" ${@: 2}"
    echo "$ $TEST_COMMAND"
    eval $TEST_COMMAND
    EXIT_STATUS=$?
else # Linux
    echo '--- :docker: Selecting Container'
    TEST_COMMAND="'\"'$MOUNTED_DIR/$1'\"' ${@: 2}"
    COMMANDS="echo \"$ $TEST_COMMAND\" && eval $TEST_COMMAND"
    . "$HELPERS_DIR/file-hash.sh" "$CICD_DIR/platforms/$PLATFORM_TYPE/$IMAGE_TAG.dockerfile"
    # --cap-add=NET_ADMIN needed to run tc (traffic control in linux kernel) inside docker for p2p_high_latency_test.py test.
    DOCKER_RUN_COMMAND="docker run --rm --init -v \"\$(pwd):$MOUNTED_DIR\" $(buildkite-intrinsics) -e JOBS -e BUILDKITE_API_KEY '$FULL_TAG' bash -c '$COMMANDS'"
    set +e # defer error handling to end
    echo "$ $DOCKER_RUN_COMMAND"
    eval $DOCKER_RUN_COMMAND
    EXIT_STATUS=$?
fi
# buildkite
if [[ "$BUILDKITE" == 'true' ]]; then
    cd build
    # upload artifacts
    echo '--- :arrow_up: Uploading Artifacts'
    echo 'Compressing core dumps...'
    [[ $((`ls -1 core.* 2>/dev/null | wc -l`)) != 0 ]] && tar czf core.tar.gz core.* || : # collect core dumps
    echo 'Exporting xUnit XML'
    mv -f ./Testing/$(ls ./Testing/ | grep '2' | tail -n 1)/Test.xml test-results.xml
    echo 'Uploading artifacts'
    [[ -f config.ini ]] && buildkite-agent artifact upload config.ini
    [[ -f core.tar.gz ]] && buildkite-agent artifact upload core.tar.gz
    [[ -f genesis.json ]] && buildkite-agent artifact upload genesis.json
    [[ -f mongod.log ]] && buildkite-agent artifact upload mongod.log
    buildkite-agent artifact upload test-results.xml
    echo 'Done uploading artifacts.'
fi
# re-throw
if [[ "$EXIT_STATUS" != '0' ]]; then
    echo "Failing due to non-zero exit status from ctest: $EXIT_STATUS"
    exit $EXIT_STATUS
fi
echo '--- :white_check_mark: Done!'
