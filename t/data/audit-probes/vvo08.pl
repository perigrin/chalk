my @a = (1,2,3); sub z { 0 } my @l = ((@a[0,1] = (7,8)), z()); print "@l\n";
