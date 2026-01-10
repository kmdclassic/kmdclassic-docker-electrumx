# Use latest Python 3 Alpine image
FROM python:3-alpine

# Install required system dependencies (build and runtime)
RUN apk add --no-cache \
    git \
    gcc \
    g++ \
    make \
    cmake \
    python3-dev \
    musl-dev \
    libffi-dev \
    openssl-dev \
    snappy \
    snappy-dev \
    curl \
    tar

# Build and install LevelDB 1.22 from source with -fPIC flag
RUN cd /tmp && \
    curl -L https://github.com/google/leveldb/archive/refs/tags/1.22.tar.gz -o leveldb-1.22.tar.gz && \
    tar -xzf leveldb-1.22.tar.gz && \
    cd leveldb-1.22 && \
    if [ -f Makefile ]; then \
        CFLAGS="-fPIC" CXXFLAGS="-fPIC" make -j$(nproc) && \
        mkdir -p /usr/local/include && \
        cp -r include/leveldb /usr/local/include/ && \
        mkdir -p /usr/local/lib && \
        (cp out-static/libleveldb.a /usr/local/lib/ 2>/dev/null || true) && \
        (cp out-shared/libleveldb.so* /usr/local/lib/ 2>/dev/null || cp out-shared/libleveldb.so /usr/local/lib/ 2>/dev/null || true); \
    elif [ -f CMakeLists.txt ]; then \
        mkdir -p build && \
        cd build && \
        cmake -DCMAKE_BUILD_TYPE=Release \
              -DCMAKE_INSTALL_PREFIX=/usr/local \
              -DCMAKE_C_FLAGS="-fPIC" \
              -DCMAKE_CXX_FLAGS="-fPIC" \
              -DBUILD_SHARED_LIBS=ON .. && \
        cmake --build . -j$(nproc) && \
        cmake --install . && \
        cd ..; \
    fi && \
    cd / && \
    rm -rf /tmp/leveldb-1.22* && \
    ldconfig

# Create working directory
WORKDIR /app

# Clone ElectrumX repository
RUN git clone https://github.com/spesmilo/electrumx.git .

# Create virtual environment
RUN python3 -m venv /app/venv

# Set environment variables for proper library linking
ENV LD_LIBRARY_PATH=/usr/lib:/usr/local/lib
ENV PKG_CONFIG_PATH=/usr/lib/pkgconfig:/usr/local/lib/pkgconfig
ENV LDFLAGS="-L/usr/lib -L/usr/local/lib -Wl,-rpath,/usr/local/lib"
ENV CPPFLAGS="-I/usr/include -I/usr/local/include"
ENV CFLAGS="-I/usr/include -I/usr/local/include"

# Verify LevelDB 1.22 installation
RUN ldconfig && \
    ls -la /usr/local/lib/libleveldb* && \
    echo "LevelDB 1.22 installed successfully"

# Upgrade pip and install plyvel separately to ensure proper compilation
# Use --no-binary to force compilation from source with system libraries
RUN /app/venv/bin/pip install --upgrade pip && \
    /app/venv/bin/pip install --no-cache-dir --force-reinstall --no-binary plyvel plyvel

# Install ElectrumX with additional packages
RUN /app/venv/bin/pip install --no-cache-dir . && \
    /app/venv/bin/pip install --no-cache-dir .[uvloop,ujson]

# Install su-exec for user switching
RUN apk add --no-cache su-exec

# Create data directory
RUN mkdir -p /data

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Add venv to PATH
ENV PATH="/app/venv/bin:$PATH"

# Set entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]

# Run ElectrumX server
CMD ["electrumx_server"]

