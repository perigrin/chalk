my $t = "ab"; sub id { "@_" } print id($t =~ tr/a//, $t = "z"), "\n";
