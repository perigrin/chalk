my $t = "abc"; sub id { "@_" } print id(lc($t), $t = "ZZZ"), "\n";
