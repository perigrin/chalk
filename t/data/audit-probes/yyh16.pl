sub c { wantarray ? "L" : "S" } sub g { if ($_[0]) { return c() } c() } my @x = g(1); my $y = g(1); my @z = g(0); my $w = g(0); print "@x$y@z$w\n";
