my @a = (1,2,3); my ($x, $y, $z) = @a; ($x, $y) = ($y, $x); my @r = ($z) x 2; ($a[0], $a[2]) = ($a[2], $a[0]); my @sw = @a[2,1,0]; (my $t, @a) = @a; print "$x$y@r@sw$t@a\n";
