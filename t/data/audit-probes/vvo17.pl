my @a = (1,2,3); my @b; push @b, (@a[0,1] = (7,8)), $a[0] = 9; print "@b\n";
