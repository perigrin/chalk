sub k { \$_[0] } my @r; my $i = 0; while ($i < 3) { my $x = ++$i; push @r, k($x) } print join(",", map { $$_ } @r), "\n";
