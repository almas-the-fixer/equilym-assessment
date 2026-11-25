#!/usr/bin/env sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <access-log-path>" >&2
  exit 2
fi

log_file=$1
if [ ! -f "$log_file" ]; then
  echo "Missing log file: $log_file" >&2
  exit 1
fi

awk '
  NF >= 4 {
    total++
    status = $2
    if (status >= 400 && status <= 499) c4xx++
    if (status >= 500 && status <= 599) c5xx++
  }
  END {
    printf "Total requests: %d\n", total
    printf "HTTP 4xx: %d\n", c4xx + 0
    printf "HTTP 5xx: %d\n", c5xx + 0
    printf "HTTP 5xx rate: %.2f%%\n", total ? (c5xx * 100 / total) : 0
  }
' "$log_file"

echo "Three most common routes:"
awk '
  NF >= 4 {
    route = $4
    sub(/\?.*/, "", route)
    routes[route]++
  }
  END {
    for (route in routes) print routes[route], route
  }
' "$log_file" | sort -k1,1nr -k2,2 | head -n 3
