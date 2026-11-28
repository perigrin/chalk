my @r; for my $i (1..3) { my @a; push @a, $i; push @r, scalar(@a) } print join(",", @r), "\n";
