CGI script implementation of https://github.com/podocarp/speedtest_exporter

The above exporter returned absurd results that the `speedtest-cli` script
never did, so I wrote this script to use with nginx on my server.

My setup for nginx:

```nginx
load_module /usr/lib/nginx/modules/ngx_http_cgi_module.so;

http {
  server {
    listen 127.0.0.1:9101;

    location / {
      cgi_pass /opt/speedtest/speedtest.sh;
    }
  }
}
```

For Prometheus add this to your config:

```yml
scrape_configs:
  - job_name: speedtest
    scrape_interval: 60m
    scrape_timeout: 60s
    static_configs:
      - targets: ["127.0.0.1:9101"]
```

Requirements:

- speedtest-cli
- uuidgen
- jq
- curl
