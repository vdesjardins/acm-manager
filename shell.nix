let
  fetchNixpkgs = fetchTarball "https://github.com/nixos/nixpkgs/archive/6bd1daaf0fe8190a48ac5d27028ef8bed3891ec7.tar.gz";
in
{ pkgs ? import fetchNixpkgs { } }:

with pkgs;

mkShell {
  buildInputs = [
    go
    gopls
    kustomize
    kubebuilder
    kind
    awscli2
    kubectl
    kubernetes-helm
    gnumake
    jq
    envsubst
  ];
}
