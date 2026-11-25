my @a = (1,2,3); my @b = map { $_++ } @a; print "@a|@b|"; my @c = grep { $_ *= 2 } @a; print "@a|@c|"; my @d = map { s/4/x/; $_ } @a; print "@a\n";
