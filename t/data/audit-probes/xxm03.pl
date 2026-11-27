my $r; for my $i (1..3) { $r = \$i if $i == 2 } print $$r, "\n";
