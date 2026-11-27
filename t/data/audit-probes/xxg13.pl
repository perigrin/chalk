my @a = (1,2); my ($p, @b) = (@a, $a[0]); (@b, $p) = ($p, @b); print "@a|$p|@b\n";
