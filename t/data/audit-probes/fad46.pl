my $x=1; sub d { die "x\n" } eval { $x = $x + 1; $x += d(); }; print "$x\n";
