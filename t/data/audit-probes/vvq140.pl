my @t = (1,2); sub id { "@_" } print id($#t, push(@t, 3)), "\n";
