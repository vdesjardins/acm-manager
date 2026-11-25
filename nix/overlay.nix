final: prev: {
  devShell = final.callPackage ./dev.nix {};
  go = prev.go_1_27.overrideAttrs (old: {
    version = "1.27.4";
    src = final.fetchurl {
      url = "https://go.dev/dl/go1.27.4.src.tar.gz";
      hash = "sha256-c8+4VxrsDAEXdofbhxY9Rqog6XeWcncokaoXZU2aYJk=";
    };
  });

  kubernetes-code-generator = prev.kubernetes-code-generator.overrideAttrs (old: rec {
    version = "0.37.2";
    src = prev.fetchFromGitHub {
      owner = "kubernetes";
      repo = "code-generator";
      tag = "v${version}";
      hash = "sha256-5c72/ySGNA1FtU0LVn4GyFvkIMUfD/FRtBgG5QrLqK4=";
    };
    vendorHash = "sha256-ZeeY4CLIwZ77pKK2yX2LoE83ij4Sp0Bs2u3xTIZOHsg=";
  });

  kubernetes-controller-tools = prev.kubernetes-controller-tools.overrideAttrs (old: rec {
    version = "0.23.0";
    src = prev.fetchFromGitHub {
      owner = "kubernetes-sigs";
      repo = "controller-tools";
      tag = "v${version}";
      hash = "sha256-BvFMLjxC5iZk9gmTgMA6ZFBHXwGzi35sz63uVB0A+xs=";
    };
    vendorHash = "sha256-eGp5KRangcOwvAEFDJrKBFZGLqB4tqK2AiltFlG4hM0=";
  });
}
