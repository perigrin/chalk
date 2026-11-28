our @keep; sub k { push @keep, \$_[0] } sub w { k($_[0]) } for my $i (1..3) { my $x = $i; w($x) } print join(",", map { $$_ } @keep), "\n";
