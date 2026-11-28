my $t = "a"; sub id { "@_" } print id(substr($t, 0, 1), $t = "zz"), "\n";
