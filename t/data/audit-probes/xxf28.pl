our @g = (1,2,3); { local $g[1] = 9; print "@g" } print "@g\n";
