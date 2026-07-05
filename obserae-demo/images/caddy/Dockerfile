# Caddy + iproute2: iproute2 is added so the container can inject, at startup,
# a return route toward the client segments (via the lab router), which keeps
# the real source IPs intact in the flow records.
FROM caddy:2-alpine
RUN apk add --no-cache iproute2
