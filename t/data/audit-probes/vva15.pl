our @g = (1,2,3); { local (@g[0,1]) = (8,9); print "@g;" } print "@g\n";
