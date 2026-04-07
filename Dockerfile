FROM alpine:3.21

RUN apk add --no-cache gettext bash

RUN addgroup -S configgen && adduser -S configgen -G configgen

RUN mkdir -p /templates /output /scripts && \
    chown configgen:configgen /output

COPY generate-config.sh /scripts/generate-config.sh

RUN chmod +x /scripts/generate-config.sh

ENV TEMPLATES_DIR=/templates
ENV OUTPUT_DIR=/output
ENV TEMPLATE_PATTERN=*.template
ENV KEEP_RUNNING=false

WORKDIR /scripts

USER configgen

CMD ["/scripts/generate-config.sh"]