my @c; for my $i (1..3) { my $x = $i; push @c, [sub { $x++ }, sub { $x }] } $c[0][0]->(); $c[0][0]->(); $c[2][0]->(); print join(",", map { $_->[1]->() } @c), "\n";
