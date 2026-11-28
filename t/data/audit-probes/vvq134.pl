my $t = "abc"; sub id { "@_" } print id($t . "", $t = "zzz"), "\n";
