sub k { \$_[0] } my @r; for my $i (1..2) { my $x = $i; for my $j (1..2) { push @r, k($x) } } print join(",", map { $$_ } @r), "\n";
