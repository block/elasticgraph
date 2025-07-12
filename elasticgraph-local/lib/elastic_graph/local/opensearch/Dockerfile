ARG VERSION=latest
FROM opensearchproject/opensearch:${VERSION}
RUN /usr/share/opensearch/bin/opensearch-plugin remove opensearch-anomaly-detection && \
    /usr/share/opensearch/bin/opensearch-plugin remove opensearch-security && \
    /usr/share/opensearch/bin/opensearch-plugin install --batch mapper-size analysis-icu
