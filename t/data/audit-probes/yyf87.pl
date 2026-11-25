my ($n,$m)=(0,0); for my $i (1..3) { eval { $n++; die "x\n" if $i == 2; $m++ } } print "$n $m\n";
