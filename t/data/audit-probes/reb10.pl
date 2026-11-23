my $n=0; for my $i (1..3) { eval { $n+=$i; die "x\n" if $i==2; $n+=10 }; } print "$n\n";
