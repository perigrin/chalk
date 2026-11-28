my @r = map { \$_ } 1..3; ${$r[0]} = 9; print join(",", map { $$_ } @r), "\n";
