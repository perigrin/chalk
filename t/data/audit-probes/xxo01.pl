our @g = (1,2,3); { local @g[0,1]; print defined $g[0] ? "d" : "u" } print "@g\n";
