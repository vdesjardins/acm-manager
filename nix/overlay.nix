final: prev: {
  devShell = final.callPackage ./dev.nix {};
  # Pin to the exact Go version (1.24.3) that matches your system installation
  # This ensures consistent behavior between system Go and project Go
  go = prev.go_1_25.overrideAttrs (old: {
    version = "1.25.1";
    src = final.fetchurl {
      url = "https://go.dev/dl/go1.25.1.src.tar.gz";
      hash = "sha256-0BDBCc7pTYDv5oHqtGvepJGskGv0ZYPDLp8NuwvRpZQ=";
    };
  });

  kubernetes-code-generator = prev.kubernetes-code-generator.overrideAttrs (old: rec {
    version = "0.34.1";
    src = prev.fetchFromGitHub {
      owner = "kubernetes";
      repo = "code-generator";
      tag = "v${version}";
      hash = "sha256-P8spl1kQdaEEjdygmd3lkhEEXvHi+gHALBTGzVfCzfs=";
    };
    vendorHash = "sha256-7IZ2B8+ArELYwK+kfOOtSiOjfqZ2K9y5sUg6Go4fAHo=";
  });

  kubernetes-controller-tools = prev.kubernetes-controller-tools.overrideAttrs (old: rec {
    version = "0.19.0";
    src = prev.fetchFromGitHub {
      owner = "kubernetes-sigs";
      repo = "controller-tools";
      tag = "v${version}";
      hash = "sha256-NPyX89Hr1MAUdMafEEvcf/geQD1PxkDFSRPCFZBh29g=";
    };
    vendorHash = "sha256-97FtwBaN8rMTsz9XbTEB1PSC454N2SLSWyOzXSWld9Y=";
  });
}
