my @r = map { my $x = $_; \$x } 1..3; print join(",", map { $$_ } @r), "\n";
