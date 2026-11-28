our $x = 1; my $s = do { local $x = 2; $x }; print "$s$x\n";
