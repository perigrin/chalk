print join("|", split(//, "abc", 2)), " ", join("|", split(/x*/, "ab", 5)), " ", join("|", split(//, "ab")), " ", join("|", split(//, "ab", -1)), " ", join("|", split(/b/, "ab", 3)), "\n";
