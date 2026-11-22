my @l = (1,2); my @r = map { bump(); $_ } @l; sub bump { $_ += 10 } print "@r|@l\n";
