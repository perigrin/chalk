my @a = (1,2,3); my @d = map { $_ > 1 ? ($_) : () } @a; print "@d\n";
