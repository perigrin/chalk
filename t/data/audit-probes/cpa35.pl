my $c = 1; my @b = $c ? (1, 3) : (); my @d = @b; $d[1] = 8; print "@b|@d\n";
