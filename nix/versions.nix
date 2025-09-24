{ lib }:

# Version matrix mapping Android kernel branches to Clang toolchains and pinned commits.
# Commits are taken from your local src/* clones.
{
  "android12-5.10" = {
    clang = "clang-r416183b";
    srcRev = "534bbffaa6341dbbbc85625f661d9754247456e9";
    srcBranch = "android12-5.10";
  };
  "android13-5.10" = {
    clang = "clang-r450784e";
    srcRev = "9270bc60703895f1d77fe7da086bb8563cb1dded";
    srcBranch = "android13-5.10";
  };
  "android13-5.15" = {
    clang = "clang-r450784e";
    srcRev = "97b631bf0f53224f08552ce02ce5c10edfc26655";
    srcBranch = "android13-5.15";
  };
  "android14-5.15" = {
    clang = "clang-r487747c";
    srcRev = "969224bb6f83b08e7a7ab928cf2c96367266c3b6";
    srcBranch = "android14-5.15";
  };
  "android14-6.1" = {
    clang = "clang-r487747c";
    srcRev = "42472e1a491371d2524e3de4c17c12a868649e3a";
    srcBranch = "android14-6.1";
  };
  "android15-6.6" = {
    clang = "clang-r510928";
    srcRev = "cac44a0bcfc58c85082b13220b4adcac43ccf369";
    srcBranch = "android15-6.6";
  };
  "android16-6.12" = {
    clang = "clang-r536225";
    srcRev = "bf0fb8bb181b86adf67dcc60b8269d60814de5a1";
    srcBranch = "android16-6.12";
  };
}

