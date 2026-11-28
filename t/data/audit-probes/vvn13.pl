my @r; for my $i (1..3) { push @r, \$i; ${$r[-1]}++; push @r, $i } print join(",", map { ref $_ ? $$_ : $_ } @r), "\n";
