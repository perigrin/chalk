sub two { my @a; ((@a[0,1] = (7,8)), $a[0] = 9) } my @l = two(); print "@l\n";
