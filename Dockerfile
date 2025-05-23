# syntax=docker/dockerfile:1
# Using cargo-chef to manage Rust build cache effectively
FROM docker.io/lukemathwalker/cargo-chef:latest-rust-1.81 as chef

WORKDIR /app
RUN apt update && apt install lld clang -y

FROM chef as planner
COPY . .
# Compute a lock-like file for our project
RUN cargo chef prepare --recipe-path recipe.json

FROM chef as builder

# Update package lists and install protobuf-compiler along with other build dependencies
RUN apt update && apt install -y protobuf-compiler lld clang

# Specify a default value for FEATURES; it could be an empty string if no features are enabled by default
ARG FEATURES=""
ARG PROFILE="release"

COPY --from=planner /app/recipe.json recipe.json
# Build our project dependencies
ENV CARGO_BUILD_JOBS=4
RUN cargo chef cook --release --recipe-path recipe.json

COPY . .
ENV SQLX_OFFLINE true

# Build the project
RUN echo "Building with profile: ${PROFILE}, features: ${FEATURES}, "
RUN cargo build --profile=${PROFILE} --features "${FEATURES}" --bin appflowy_cloud

FROM docker.io/debian:bookworm-slim AS runtime
WORKDIR /app
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends openssl ca-certificates curl \
  && update-ca-certificates \
  # Clean up
  && apt-get autoremove -y \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/appflowy_cloud /usr/local/bin/appflowy_cloud
ENV APP_ENVIRONMENT production
ENV RUST_BACKTRACE 1

ARG APPFLOWY_APPLICATION_PORT
ARG PORT
ENV PORT=${APPFLOWY_APPLICATION_PORT:-${PORT:-8000}}
EXPOSE $PORT

CMD ["appflowy_cloud"]
