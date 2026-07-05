# labtools: shared utility image for the lab (router, sensor, DNS, backend, workstations).
# Ubuntu base because softflowd ships in the "universe" repository.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      tini \
      iproute2 \
      iputils-ping \
      ca-certificates \
      curl \
      dnsutils \
      netcat-openbsd \
      nmap \
      softflowd \
      dnsmasq \
      postgresql-client \
      python3 \
      python3-flask \
      python3-psycopg2 \
 && rm -rf /var/lib/apt/lists/*

# tini handles signals cleanly (graceful container shutdown).
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sleep", "infinity"]
