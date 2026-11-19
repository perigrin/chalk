our @g = (1); sub t { local @g = (@g, 2); return scalar @g } print t(), scalar(@g), "\n";
