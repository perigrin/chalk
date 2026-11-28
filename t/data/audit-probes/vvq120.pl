my $t = "abc"; sub id { "@_" } print id(substr($t, 1), chop $t), "\n";
