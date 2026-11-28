my @r; sub g { for my $i (1..$_[0]) { push @r, \$i; g($_[0] - 1) } } g(2); print join(",", map { $$_ } @r), "\n";
