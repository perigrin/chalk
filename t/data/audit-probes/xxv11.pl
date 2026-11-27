my $s = "ab"; my $n = ($s =~ tr/a/x/); sub id { $_[0] } print id($s), $n, "\n";
