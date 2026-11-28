sub as { ($_[0], $_[1]) = ($_[1], $_[0]) } my ($p, $q) = (1, 2); my @l = as($p, $q); print "$p$q|@l\n";
