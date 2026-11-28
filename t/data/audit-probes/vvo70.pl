my @a = (1); my @l = (($a[0] = 7), $a[0] = 9); print "@l\n";
