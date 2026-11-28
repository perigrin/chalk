sub k { \$_[0] } my @r; for my $i (1..3) { push @r, k($i) } print join(",", map { $$_ } @r), "\n";
