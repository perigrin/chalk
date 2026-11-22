sub g { return @_ } my ($x, $y); ($x, $y) = g(1, 2); my $s = "$x$y"; ($x, $y) = g(3, 4); print "$s $x$y\n";
