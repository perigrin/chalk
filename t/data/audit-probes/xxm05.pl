my @r = map { \$_ } 1..3; print join(",", map { $$_ } @r), "\n";
