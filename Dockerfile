# An example using multi-stage image builds to create a final image without uv.

# First, build the application in the `/app` directory.
# See `Dockerfile` for details.
FROM ghcr.io/astral-sh/uv:python3.11-alpine AS builder

# Install build dependencies for compiling Rust extensions (pydantic-core)
RUN apk add --no-cache gcc musl-dev cargo

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

# Omit development dependencies
ENV UV_NO_DEV=1

# Disable Python downloads, because we want to use the system interpreter
# across both images. If using a managed Python version, it needs to be
# copied from the build image into the final image; see `standalone.Dockerfile`
# for an example.
ENV UV_PYTHON_DOWNLOADS=0

WORKDIR /app
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project
COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked

# Verify the build by validating imports and tool registration
RUN python readeck-mcp.py validate


# Then, use a final image without uv (matching Alpine base)
FROM python:3.11-alpine
# It is important to use the image that matches the builder (python3.11-alpine),
# as the path to the Python executable must be the same.

# Copy the application from the builder
COPY --from=builder --chown=nonroot:nonroot /app /app

# Place executables in the environment at the front of the path
ENV PATH="/app/.venv/bin:$PATH"

# Use `/app` as the working directory
WORKDIR /app

# Add healthcheck (SSE endpoint should respond with connection)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/sse || exit 1

# Run the MCP server in HTTP mode by default
# For stdio mode (desktop clients), run: docker run <image> python readeck-mcp.py
CMD ["python", "readeck-mcp.py", "serve", "0.0.0.0", "8080"]
