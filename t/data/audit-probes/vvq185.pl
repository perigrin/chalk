my @a = (1); my @l = do { (@a, $a[0]++) }; print "@l\n";
