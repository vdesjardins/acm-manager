final: prev: {
  devShell = final.callPackage ./dev.nix {};
  go = prev.go_1_25.overrideAttrs (old: {
    version = "1.25.7";
    src = final.fetchurl {
      url = "https://go.dev/dl/go1.25.7.src.tar.gz";
      hash = "sha256-F48oMoICdLQ+F30y8Go+uwEp5CfdIKXkyI3ywXY88Qo=";
    };
  });

  kubernetes-code-generator = prev.kubernetes-code-generator.overrideAttrs (old: rec {
    version = "0.35.0";
    src = prev.fetchFromGitHub {
      owner = "kubernetes";
      repo = "code-generator";
      tag = "v${version}";
      hash = "sha256-uFFu9Lkz119qUmf1hWSfudRjgTw5TEaSHpVUi2jIaJs=";
    };
    vendorHash = "sha256-Peo/i4wLwnbvRPTFoAKQ7CzZxSKaKkm2RNomODluJTc=";
  });

  kubernetes-controller-tools = prev.kubernetes-controller-tools.overrideAttrs (old: rec {
    version = "0.20.0";
    src = prev.fetchFromGitHub {
      owner = "kubernetes-sigs";
      repo = "controller-tools";
      tag = "v${version}";
      hash = "sha256-Cjn8o5AhmIE9UFT38cyIUnT/3pG1dJGWivYvVIbUAAk=";
    };
    vendorHash = "sha256-cFnUfcoLyFHg0JR6ix0AnpSHUGuNNVbKldKelvvMu/4=";
  });
}
