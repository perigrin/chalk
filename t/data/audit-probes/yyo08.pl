use File::Spec; print File::Spec->catfile("a", "b", "c.txt"), " ", File::Spec->catdir("x", "y"), " ", File::Spec->canonpath("/a/./b//c/"), " ", join("|", File::Spec->splitdir("/a/b")), "\n";
