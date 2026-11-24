my $r = do { eval { die "x\n" }; $@ ? "e" : "n" }; print "$r\n";
