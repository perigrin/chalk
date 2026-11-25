sub f { unless ($_[0]) { "x" } } my @r = f(1); my $s = f(1); print scalar(@r), "[@r][$s]\n";
