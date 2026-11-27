our @g = (1,2,3); my @i = (0,2); { local @g[@i] = (8,9); } print "@g\n";
