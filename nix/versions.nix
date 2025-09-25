{ lib }:

# Version matrix mapping Android kernel branches to Clang toolchains and pinned commits.
# Commits are taken from your local src/* clones.
{
  "android12-5.10" = {
    clang = "clang-r416183b";
    srcRev = "534bbffaa6341dbbbc85625f661d9754247456e9";
    srcBranch = "android12-5.10";
    # SRI for pkgs.fetchgit; computed via: nix run nixpkgs#nix-prefetch-git -- https://android.googlesource.com/kernel/common --rev <srcRev>
    srcSha256 = "sha256-j6x35fjDeJ9ntYvi3N5jyFhdT+3wvmn3QJK0KbEobBc=";
  };
  "android13-5.10" = {
    clang = "clang-r450784e";
    srcRev = "9270bc60703895f1d77fe7da086bb8563cb1dded";
    srcBranch = "android13-5.10";
    srcSha256 = "sha256-+ffm2v9597IaIpTsGxm3xyBAT55BjgbdzqgeO7NTiMI=";
  };
  "android13-5.15" = {
    clang = "clang-r450784e";
    srcRev = "97b631bf0f53224f08552ce02ce5c10edfc26655";
    srcBranch = "android13-5.15";
    srcSha256 = "sha256-OKAbzqffW/t+6sBDz/ag57rP6g0BzT3oMx4q/q7AR+4=";
  };
  "android14-5.15" = {
    clang = "clang-r487747c";
    srcRev = "969224bb6f83b08e7a7ab928cf2c96367266c3b6";
    srcBranch = "android14-5.15";
    srcSha256 = "sha256-nYvuaqTgVCAgLJjYVnIDfJBqsfETtUkCzCbZL6NnV/0=";
  };
  "android14-6.1" = {
    clang = "clang-r487747c";
    srcRev = "42472e1a491371d2524e3de4c17c12a868649e3a";
    srcBranch = "android14-6.1";
    srcSha256 = "sha256-mJfVBf+qCuknJqMJLz07kmzUnEAjZAnui9cmewzuEx0=";
  };
  "android15-6.6" = {
    clang = "clang-r510928";
    srcRev = "cac44a0bcfc58c85082b13220b4adcac43ccf369";
    srcBranch = "android15-6.6";
    srcSha256 = "sha256-zFhzZwV4YXj/V3oPjstufZWqrBHPqGPnMPsV6eK8X4o=";
  };
  "android16-6.12" = {
    clang = "clang-r536225";
    srcRev = "bf0fb8bb181b86adf67dcc60b8269d60814de5a1";
    srcBranch = "android16-6.12";
    srcSha256 = "sha256-UWeEgRcVaBxvLPywYpysJuKbq3r88qpMqABH5k+fTFg=";
  };
}
