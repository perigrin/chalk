our @keep; my $k = sub { push @keep, \$_[0] }; for my $i (1..3) { my $x = $i; $k->($x) } print join(",", map { $$_ } @keep), "\n";
