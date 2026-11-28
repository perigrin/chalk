my @a = (1); my @l = do { ($a[0], $a[0]++) }; print "@l\n";
