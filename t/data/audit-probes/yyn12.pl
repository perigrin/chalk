my $n = 0; for my $i (1..5) { eval { last if $i == 3; $n += $i; 1 } } print "$n\n";
