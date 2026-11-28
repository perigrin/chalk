my @t = (1,2); sub id { "@_" } print id($t[$#t], push(@t, 3)), "\n";
