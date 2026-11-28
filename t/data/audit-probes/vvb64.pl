sub mk { my $x = shift; \$x } my @r = map { mk($_) } 1..3; print join(",", map { $$_ } @r), "\n";
