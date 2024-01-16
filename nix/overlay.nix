final: prev: {
  devShell = final.callPackage ./dev.nix {};
  go = final.go_1_21;
}
