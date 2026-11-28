my $t = "abc"; sub id { "@_" } print id(uc $t, $t = "zzz"), "\n";
