my @a = (1,2,3); my @b = (shift(@a), pop(@a)); unshift @a, 0; push @a, 4; print "@a|@b\n";
