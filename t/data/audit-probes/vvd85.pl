our @a = (1,2,3); my ($p, $q) = @a[0,1] = @a[1,2]; print "$p$q@a\n";
