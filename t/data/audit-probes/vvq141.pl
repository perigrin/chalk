my @t = (1,2); sub id { "@_" } print id(scalar(@t), push(@t, 3)), "\n";
