my @log; sub d { push @log,"d"; die "x\n" } for my $i (1..2) { eval { push @log,$i; d() }; push @log,"c" } print "@log\n";
