my $s = "abc"; if ($s =~ /(a)/) { my $t = do { "x" =~ /(x)/; $1 }; print "$t$1" } print "\n";
