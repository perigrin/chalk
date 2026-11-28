my @r; push @r, \$_ for 1..3; print join(",", map { $$_ } @r), "\n";
