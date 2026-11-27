my @a = (1,2,3); my ($x,$y) = @a[1,2]; ($x,$y) = @a[0,1] = ($y,$x); print "$x$y@a\n";
