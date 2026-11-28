my $t = "ab"; sub id { "@_" } print id($t x 2, $t = "z"), "\n";
