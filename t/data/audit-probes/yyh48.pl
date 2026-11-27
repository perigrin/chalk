my @a = (1) x 3; my @b = (1,2) x 2; my @c = ((1,2) x 2, 3); my $s = (1,2) x 2; my @d = (0) x @a; print "@a|@b|@c|$s|@d\n";
