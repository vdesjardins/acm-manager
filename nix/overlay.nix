final: prev: {
  devShell = final.callPackage ./dev.nix {};
  go = prev.go_1_26.overrideAttrs (old: {
    version = "1.26.7";
    src = final.fetchurl {
      url = "https://go.dev/dl/go1.26.7.src.tar.gz";
      hash = "sha256-DtJOrHVRBQhbif6cq8J0K5GgrXuUtZ0602SRjryJVq0=";
    };
  });

  kubernetes-code-generator = prev.kubernetes-code-generator.overrideAttrs (old: rec {
    version = "0.36.4";
    src = prev.fetchFromGitHub {
      owner = "kubernetes";
      repo = "code-generator";
      tag = "v${version}";
      hash = "sha256-nvE8SYEJuIMo5CcY/l9HUQiU8OQfb2+7CfhUlq3W0sA=";
    };
    vendorHash = "sha256-Ahj8sV4o8XxuRipsxtPVdY1Nkvm7T1uSHzRnq26Qo1Y=";
  });

  kubernetes-controller-tools = prev.kubernetes-controller-tools.overrideAttrs (old: rec {
    version = "0.21.0";
    src = prev.fetchFromGitHub {
      owner = "kubernetes-sigs";
      repo = "controller-tools";
      tag = "v${version}";
      hash = "sha256-4IkVnD87/sHZKixDaF9Qz95cdChPfOkEowBQwu7kq9Y=";
    };
    vendorHash = "sha256-LNjd0PDVa4GMY1rFJ5PFiWAEeA5MMraIIzZmYgkdgJc=";
  });
}
