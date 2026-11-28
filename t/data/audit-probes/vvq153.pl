my $t = "ab"; sub id { "@_" } print id($t =~ s/a/b/r, $t = "z"), "\n";
