my $t = "ab"; sub id { "@_" } print id($t =~ /(a)/, $t = "z"), "\n";
