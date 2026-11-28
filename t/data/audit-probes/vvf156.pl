my @a = (1,2,3); my @l = ($a[0], shift(@a), $a[0]); print "@l\n";
