our @keep; sub k { push @keep, \@_ } for my $i (1..3) { my $x = $i; k($x) } print join(",", map { $_->[0] } @keep), "\n";
