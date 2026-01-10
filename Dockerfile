# Use latest Python 3 Alpine image
FROM python:3-alpine

# Install required system dependencies
RUN apk add --no-cache \
    git \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev

# Create working directory
WORKDIR /app

# Clone ElectrumX repository
RUN git clone https://github.com/spesmilo/electrumx.git .

# Create virtual environment
RUN python3 -m venv /app/venv

# Activate venv and install ElectrumX with additional packages
RUN /app/venv/bin/pip install --upgrade pip && \
    /app/venv/bin/pip install . && \
    /app/venv/bin/pip install .[uvloop,ujson]

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

