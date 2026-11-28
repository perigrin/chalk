our @keep; sub k { push @keep, \$_[0] } for my $i (1..3) { my $x = $i; k($x); $x *= 2 } print join(",", map { $$_ } @keep), "\n";
