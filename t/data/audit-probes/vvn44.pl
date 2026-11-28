our @keep; sub k { push @keep, \$_[0] } for my $i (1..3) { k($i); $i *= 2 } print join(",", map { $$_ } @keep), "\n";
