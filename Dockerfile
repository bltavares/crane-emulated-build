FROM ubuntu:latest
RUN apt update -y
RUN apt install curl git -y
RUN curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux \
  --extra-conf "sandbox = false" \
  --init none \
  --no-confirm \
  --extra-conf "extra-platforms = x86_64-linux aarch64-linux"
ENV PATH="${PATH}:/nix/var/nix/profiles/default/bin"
RUN nix run nixpkgs#hello --system aarch64-linux
RUN nix run nixpkgs#hello --system x86_64-linux