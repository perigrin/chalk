my @a = (1..5); my @b = splice(@a, 1, 2, "x", "y", "z"); my @c = splice(@a, -1); splice(@a, 1, 0, "i"); my @d = splice(@a, 3); print "@a|@b|@c|@d\n";
