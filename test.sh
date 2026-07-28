#!/bin/sh
set -eu

cd "$(dirname "$0")"

TEST_BINARY=".build/AIUsageRegressionTests"
mkdir -p .build

swiftc -parse-as-library \
    Sources/AIUsage/Report.swift \
    Sources/AIUsage/Pace.swift \
    Sources/AIUsage/Fetcher.swift \
    Tests/RegressionTests.swift \
    -o "$TEST_BINARY"

"$TEST_BINARY"
