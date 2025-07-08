# Kodi Base Image Builder
FROM registry.fedoraproject.org/fedora:42 AS builder

# Install build dependencies including ccache
COPY scripts/install-dependencies.sh /tmp/
RUN chmod +x /tmp/install-dependencies.sh && \
    /tmp/install-dependencies.sh && \
    dnf install -y ccache && \
    dnf clean all

# Configure ccache
ENV CCACHE_DIR=/ccache
ENV CCACHE_MAXSIZE=5G
ENV CCACHE_COMPRESS=1
ENV CCACHE_COMPRESSLEVEL=6
ENV CCACHE_HARDLINK=1
ENV PATH=/usr/lib64/ccache:$PATH

# Create ccache directory
RUN mkdir -p ${CCACHE_DIR} && chmod 777 ${CCACHE_DIR}

# Build Kodi
COPY scripts/build-kodi.sh /tmp/
RUN --mount=type=cache,target=/ccache \
    chmod +x /tmp/build-kodi.sh && \
    /tmp/build-kodi.sh

# Create runtime dependencies list using only ldd
RUN dnf install -y dnf-utils && \
    echo "Discovering runtime dependencies using ldd..." && \
    { \
        # Find all Kodi binaries and libraries
        find /usr/bin -name "kodi*" -type f -executable -print0 | \
            xargs -0 -I {} ldd {} 2>/dev/null | grep "=>" | awk '{print $3}' | sort -u; \
        find /usr/lib64/kodi -type f \( -name "*.so" -o -perm -111 \) -print0 | \
            xargs -0 -I {} ldd {} 2>/dev/null | grep "=>" | awk '{print $3}' | sort -u; \
        find /usr/share/kodi -type f -name "*.so" -print0 | \
            xargs -0 -I {} ldd {} 2>/dev/null | grep "=>" | awk '{print $3}' | sort -u; \
    } | sort -u | \
    while read lib; do \
        rpm -qf "$lib" 2>/dev/null || true; \
    done | \
    grep -v "file.*not owned" | \
    sort -u > /runtime-deps.txt && \
    echo "Found $(wc -l < /runtime-deps.txt) runtime dependencies:" && \
    cat /runtime-deps.txt


# Final minimal image with just Kodi binaries
FROM scratch AS final

# Copy Kodi installation
COPY --from=builder /usr/lib64/kodi /usr/lib64/kodi
COPY --from=builder /usr/lib/kodi /usr/lib/kodi
COPY --from=builder /usr/bin/kodi* /usr/bin/
COPY --from=builder /usr/share/kodi /usr/share/kodi
COPY --from=builder /usr/share/metainfo/*kodi* /usr/share/metainfo/
COPY --from=builder /usr/lib/firewalld/services/*kodi* /usr/lib/firewalld/services/

# Copy runtime dependencies list
COPY --from=builder /runtime-deps.txt /


# Metadata
LABEL org.opencontainers.image.title="Kodi GBM/HDR Base"
LABEL org.opencontainers.image.description="Pre-built Kodi with GBM and HDR support"
LABEL org.opencontainers.image.vendor="Blahkaey"
