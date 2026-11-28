my $t = 5; sub id { "@_" } print id($t++, $t = 6), "\n";
