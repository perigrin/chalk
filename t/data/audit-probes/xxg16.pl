my ($x,$y) = (1,2); my @r = (($x,$y) = ($y,$x)); $r[0] = 9; print "$x$y@r\n";
