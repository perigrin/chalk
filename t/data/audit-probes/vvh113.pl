my $o = {n => 1}; sub d { die "x\n" } eval { $o->{n} = 2; $o->{m} = d(); $o->{n} = 3 }; print $o->{n}, "\n";
