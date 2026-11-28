my $t = "ab"; sub id { "@_" } print id($t =~ tr/a/b/r, $t = "z"), "\n";
