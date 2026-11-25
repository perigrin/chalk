sub f { if ($_[0]) { "t" } } my @r = f(0); my $s = f(0); my @t = f(1); print scalar(@r), "[@r][$s][@t]\n";
