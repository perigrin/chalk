my @a = (1); sub z { $a[0] = 9; 0 } my @l = (($a[0] = 7), z()); print "@l\n";
