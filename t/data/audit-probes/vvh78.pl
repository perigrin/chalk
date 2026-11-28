my $r = do { eval { die "x\n" }; $@ ? "c" : "n" }; print "$r\n";
