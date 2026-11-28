sub f { $_[0]++ } my $t = 0; for my $i (1..3) { my $y = $i; eval { f($y); die "x\n" }; $t += $y } print "$t\n";
