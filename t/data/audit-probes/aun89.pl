my $x = 1; sub f { die "x\n" } eval { $x = 2; f(); $x = 3 }; print "$x\n";
