my $c = 1; my @a = (time % 1 + 1, 2); my @b = $c ? ($a[0], 3) : (); my @d = @b; $d[0] = 9; print "@b|@d\n";
