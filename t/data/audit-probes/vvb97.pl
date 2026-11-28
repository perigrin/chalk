our @keep; sub k { push @keep, \$_[1] } for my $i (1..3) { my $x = $i; my $y = $i * 2; k($x, $y) } print join(",", map { $$_ } @keep), "\n";
