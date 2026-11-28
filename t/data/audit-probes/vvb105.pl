our @keep; sub k { push @keep, \$_[0] } sub lp { for my $i (1..3) { my $x = $i; k($x) } } lp(); lp(); print join(",", map { $$_ } @keep), "\n";
