my ($x, $y); sub ctx { wantarray ? "l" : "s" } ($x, $y) = (ctx(), ctx()); my $z = ctx(); my ($w) = ctx(); print "$x$y$z$w\n";
