our $x = 1; my $s = do { local $x = 2; $x + 1 }; print "$s$x\n";
