our @keep; sub k { push @keep, \$_[0] } for my $i (1..3) { $i *= 2; k($i) } print join(",", map { $$_ } @keep), "\n";
