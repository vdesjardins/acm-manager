{ go
, gopls
, kustomize
, kubebuilder
, kind
, awscli2
, kubectl
, kubernetes-helm
, gnumake
, jq
, envsubst
, chart-testing
, mkShell
}:
mkShell {
  packages = [
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
    chart-testing
  ];
}
