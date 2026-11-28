our @keep; sub k { push @keep, \$_[0] } for my $i (1..3) { my @a = ($i); k($a[0]) } print join(",", map { $$_ } @keep), "\n";
