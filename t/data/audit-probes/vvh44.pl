our @g = (1,2); eval { local @g = (3); die "x\n" }; print "@g\n";
