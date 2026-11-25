my @a = (1,2); for (map { $_ } @a) { $_++ } print "@a|"; my @b = map { $_ } @a; $b[0]++; my @c = grep { 1 } @a; $c[0]++; print "@a|"; $_++ for grep { 1 } @a; print "@a\n";
