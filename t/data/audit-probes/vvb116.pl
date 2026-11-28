my @c; my @a = (1,2,3); while (defined(my $e = shift @a)) { push @c, \$e } print join(",", map { $$_ } @c), "\n";
