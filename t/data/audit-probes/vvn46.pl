our @keep; sub k { push @keep, \$_[0] } for my $i (1..3) { my $x = $i; $x *= 2; k($x) } print join(",", map { $$_ } @keep), "\n";
