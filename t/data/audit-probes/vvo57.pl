my @a; sub z { $a[0] = 9; 0 } my @l = ((@a = (7,8)), z()); print "@l\n";
