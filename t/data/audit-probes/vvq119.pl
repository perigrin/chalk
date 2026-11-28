my $t = "abc"; sub id { "@_" } print id(substr($t, 1, 1), $t =~ s/b/z/), "\n";
