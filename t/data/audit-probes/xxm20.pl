sub mk { my $x = shift; \$x } my @r = map { mk($_) } 1..3; ${$r[0]} = 9; print join(",", map { $$_ } @r), "\n";
