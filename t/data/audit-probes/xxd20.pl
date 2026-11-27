my @c; for my $i (1..3) { my $j = $i; push @c, sub { $j += $_[0] } } $c[0]->(10); print join(",", map { $_->(0) } @c), "\n";
