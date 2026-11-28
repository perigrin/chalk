our @keep; sub k { push @keep, \$_[0] } for my $i (1..2) { my $x = $i; for my $j (1..2) { k($x) } } ${$keep[0]} = 9; print join(",", map { $$_ } @keep), "\n";
