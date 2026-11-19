our @st = (1); sub t { local @st = (@st, 2); return scalar @st } print t(), scalar(@st), "\n";
