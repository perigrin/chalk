my @a = (1,2,3); my @l = ((@a[0,1] = (7,8)), pop @a); print "@l\n";
