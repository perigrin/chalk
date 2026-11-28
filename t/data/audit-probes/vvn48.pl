our @keep; sub k { push @keep, \$_[0] } for my $i (1..3) { my $x = $i; k($x); ${$keep[-1]} += 5; push @keep, \(my $c = $x) } print join(",", map { $$_ } @keep), "\n";
