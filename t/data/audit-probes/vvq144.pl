my $t = "ab"; sub id { "@_" } print id(reverse($t), $t = "z"), "\n";
