my @r; sub g { my $x = $_[0]; push @r, \$x; g($x - 1) if $x > 1 } g(3); print join(",", map { $$_ } @r), "\n";
