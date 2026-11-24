my $c = 1; my @b = $c ? (1, 3) : (); my @d = @b; push @b, 4; $b[0] = 7; print "@b|@d\n";
