final: prev: {
  devShell = final.callPackage ./dev.nix {};
  # Pin to the exact Go version (1.24.3) that matches your system installation
  # This ensures consistent behavior between system Go and project Go
  go = prev.go_1_24.overrideAttrs (old: {
    version = "1.24.3";
    src = final.fetchurl {
      url = "https://go.dev/dl/go1.24.3.src.tar.gz";
      hash = "sha256-IpwItgCxRGeYEJ+uH1aSKBAshHPKuoEEtkGMtbwDKHg=";
    };
  });

  kubernetes-code-generator = prev.kubernetes-code-generator.overrideAttrs (old: rec {
    version = "0.32.1";
    src = prev.fetchFromGitHub {
      owner = "kubernetes";
      repo = "code-generator";
      tag = "v${version}";
      hash = "sha256-wmiLZtGDsR1YFuAR3qHaRKasVBwT6krH+8hMh0bj7+w=";
    };
    vendorHash = "sha256-Z+hRloE6sLq79MIvjnpAoxwDj9f0zZxv7pMAF4em+vk=";
  });

  kubernetes-controller-tools = prev.kubernetes-controller-tools.overrideAttrs (old: rec {
    version = "0.16.4";
    src = prev.fetchFromGitHub {
      owner = "kubernetes-sigs";
      repo = "controller-tools";
      tag = "v${version}";
      hash = "sha256-+YDYpTfWWPkAXcCNfkk0PTWqOAGwqiABbop/t6is2nM=";
    };
    vendorHash = "sha256-zWvFwYHqECga1E2lWVA+wqY744OLXzRxK6JkniTZN70=";
  });
}
