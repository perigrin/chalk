my @a = (1, 2); if (@a) { @a[0, 1] = (3, 4) } print "@a\n"; if (!@a) { @a[0, 1] = (5, 6) } print "@a\n";
