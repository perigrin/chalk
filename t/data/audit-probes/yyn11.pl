my $n = 0; for my $i (1..5) { eval { next if $i == 2; $n += $i; }; } print "$n\n";
