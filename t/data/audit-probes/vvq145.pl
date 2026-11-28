my $t = "ab"; sub id { "@_" } print id(scalar(reverse($t)), $t = "z"), "\n";
