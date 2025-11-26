#############################################
# Alpine 3.22.2 multi-stage Dockerfile
#############################################

# --- Toolchain base (build tooling + ghcup/ghc/cabal) ---
FROM alpine:3.22.2 AS toolchain
SHELL ["/bin/sh","-eo","pipefail","-c"]

RUN set -eux; apk add --no-cache \
    bash curl ca-certificates git gnupg \
    build-base coreutils findutils python3 tar binutils \
    linux-headers libstdc++ patch diffutils sed gawk \
    gmp gmp-dev zlib zlib-dev \
    ncurses ncurses-dev ncurses-terminfo libffi libffi-dev \
    libatomic xz xz-dev perl tzdata \
    pkgconf \
    pcre pcre-dev \
    postgresql-dev \
    gcc g++ make musl-dev pkgconfig \
    && update-ca-certificates

SHELL ["/bin/bash","-o","errexit","-o","nounset","-o","pipefail","-c"]

ENV BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
    GHCUP_INSTALL_BASE_PREFIX=/root \
    GHCUP_USE_XDG_DIRS=false \
    BOOTSTRAP_HASKELL_MINIMAL=1 \
    CABAL_DIR=/root/.cabal

RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh -s -- --no-modify-path

ENV PATH="/root/.ghcup/bin:/root/.local/bin:${PATH}"

RUN set -eux; \
    ghcup upgrade; \
    ghcup install ghc 9.10.3; \
    ghcup set ghc 9.10.3; \
    ghcup install cabal 3.16.0.0; \
    ghcup set cabal 3.16.0.0



# --- Dependencies stage (shared cache between ci and build) ---
FROM toolchain AS deps
SHELL ["/bin/bash","-o","errexit","-o","nounset","-o","pipefail","-c"]
WORKDIR /app

COPY cabal.project* ./
COPY ./*.cabal ./
COPY qrcode-core/*.cabal qrcode-core/
COPY qrcode-juicypixels/*.cabal qrcode-juicypixels/
RUN cabal update

RUN cabal build all --only-dependencies -j


# --- Devcontainer stage (no build, extra tools only) ---
FROM toolchain AS devcontainer
SHELL ["/bin/bash","-o","errexit","-o","nounset","-o","pipefail","-c"]

RUN apk add --no-cache ripgrep jq util-linux-misc openssh-client just docker-cli nodejs npm

RUN set -eux; \
    ghcup --verbose install stack 3.7.1; \
    ghcup set stack 3.7.1; \
    stack --version

RUN set -eux; \
    stack config set install-ghc false --global; \
    stack config set system-ghc true --global; \
    stack path --compiler-bin

RUN set -euxo pipefail; \
    script -qec "ghcup compile hls --version 2.12.0.0 --ghc 9.10.3 --cabal-update" /dev/null; \
    ghcup set hls 2.12.0.0

RUN set -eux; \
    cabal update; \
    cabal install fourmolu-0.19.0.1 hpack --install-method=copy --installdir=/usr/local/bin

WORKDIR /workspaces/qrcode
