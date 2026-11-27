my $r; for my $i (1..3) { $r //= \$i } print $$r, "\n";
