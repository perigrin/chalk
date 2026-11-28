our @keep; sub k { push @keep, \$_[0] } for my $i (1..3) { my $x = $i; k($x) for 1..2 } ${$keep[0]} = 9; print join(",", map { $$_ } @keep), "\n";
