# .ide/Dockerfile
FROM cnbcool/default-dev-env:latest

RUN apt-get install -y xz-utils sudo

# Install Nix
RUN sh <(curl -L https://nixos.org/nix/install) --daemon --yes

ENV PATH=/nix/var/nix/profiles/default/bin:/root/.nix-profile/bin:/root/.nix-profile/sbin:$PATH \
    NIX_PATH=nixpkgs=/root/.nix-defexpr/channels/nixpkgs \
    NIX_CONFIG="experimental-features = nix-command flakes" \
    LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8
