our @g = (1,2,3); for my $i (0,1) { local @g[$i,$i+1] = (7,7); print "@g;" } print "@g\n";
