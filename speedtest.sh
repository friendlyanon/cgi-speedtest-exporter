#!/bin/sh

here=${0%/*}
script=${0##/*}

case ${TRACE-} in '' | 0) ;; *) set -x ;; esac

case $REQUEST_METHOD in GET) ;; *)
  printf 'Status: 405 Method Not Allowed\nContent-Type: text/plain\nAllow: GET\n\nError: Only GET requests are allowed\n'
  exit 0
  ;;
esac

get_root() {
  printf 'Content-Type: text/html\n\n'
  cat << 'EOF'
<!DOCTYPE html>
<html>
<head><meta charset="utf8"><title>Speedtest Exporter</title></head>
<body>
<h1>Speedtest Exporter</h1>
<p>Metrics page will take approx 40 seconds to load and show results, as the exporter carries out a speedtest when scraped.</p>
<p><a href="/metrics">Metrics</a></p>
<p><a href="/health">Health</a></p>
</body>
</html>
EOF
  exit 0
}

map_curl_code()
case $1 in
  6) printf 'DNS error' ;;
  7) printf 'Internet unreachable' ;;
  28) printf 'Timeout error' ;;
  *) printf 'General error' ;;
esac

get_health() {
  if curl -s -o /dev/null -L -I --connect-timeout 5 http://google.com 2> /dev/null
  then printf 'Content-Type: text/plain\n\nOK\n'
  else printf 'Status: 503 Service Unavailable\nContent-Type: text/plain\n\n%s\n' "$(map_curl_code $?)"
  fi
  exit 0
}

get_404() {
  printf 'Status: 404 Not Found\nContent-Type: text/plain\n\nNot Found\n'
  exit 0
}

case $PATH_INFO in
  /) get_root ;;
  /health) get_health ;;
  /metrics) ;;
  *) get_404 ;;
esac

excludes_file=$here/excludes

add_faulty() {
  faulty=$(jq -r .server.id /tmp/speedtest-out)
  printf %s\\n "$faulty" >> "$excludes_file"
  printf '[%s] Excluded server %d: bogus latency measurement\n' "$script" "$faulty" >&2
}

make_excludes() {
  test -f "$1" || return 0
  while read id _
  do printf ' --exclude %s' "$id"
  done < "$1"
}

while :
do
  if duration=$(time -p sh -c "speedtest-cli --json --secure$(make_excludes "$excludes_file") > /tmp/speedtest-out 2> /tmp/speedtest-err" 2>&1)
  then printf 'Content-Type: text/plain; version=0.0.4\n\n'
  else
    printf 'Status: 500 Internal Server Error\nContent-Type: text/plain\n\n'
    cat /tmp/speedtest-err
    exit 0
  fi

  case $(jq -r .ping /tmp/speedtest-out) in
    1800000) add_faulty ;;
    *) break ;;
  esac
done

duration=${duration%%$'\n'*}
jq --arg uuid "$(uuidgen)" --arg duration "${duration#* }" -r '
"distance=\"\(.server.d)\",server_country=\"\(.server.country)\",server_id=\"\(.server.id)\",server_lat=\"\(.server.lat)\",server_lon=\"\(.server.lon)\",server_name=\"\(.server.name)\",test_uuid=\"\($uuid)\",user_ip=\"\(.client.ip)\",user_isp=\"\(.client.isp)\",user_lat=\"\(.client.lat)\",user_lon=\"\(.client.lon)\"" as $labels |
"# HELP speedtest_download_speed_Bps Last download speedtest result",
"# TYPE speedtest_download_speed_Bps gauge",
"speedtest_download_speed_Bps{\($labels)} \(.download)",
"# HELP speedtest_latency_seconds Measured latency on last speed test",
"# TYPE speedtest_latency_seconds gauge",
"speedtest_latency_seconds{\($labels)} \(.ping / 1000)",
"# HELP speedtest_scrape_duration_seconds Time to preform last speed test",
"# TYPE speedtest_scrape_duration_seconds gauge",
"speedtest_scrape_duration_seconds{test_uuid=\"\($uuid)\"} \($duration)",
"# HELP speedtest_up Was the last speedtest successful.",
"# TYPE speedtest_up gauge",
"speedtest_up{test_uuid=\"\($uuid)\"} 1",
"# HELP speedtest_upload_speed_Bps Last upload speedtest result",
"# TYPE speedtest_upload_speed_Bps gauge",
"speedtest_upload_speed_Bps{\($labels)} \(.upload)"
' /tmp/speedtest-out

exit 0
