my @r; for my $i (1..3) { my @a = ($i); push @r, \@a } print join(",", map { "@$_" } @r), "\n";
