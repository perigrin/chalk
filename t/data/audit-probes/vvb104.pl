our @keep; sub k { push @keep, \$_[0] } my $x; for my $i (1..3) { $x = $i; k($x) } print join(",", map { $$_ } @keep), "\n";
