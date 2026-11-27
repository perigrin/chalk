our @g = (1,2,3); eval { local @g[0,1] = (8,9); die "x\n" }; print "@g\n";
