our ($x,$y)=(1,2); my @g = grep { $_ > 1 } $x,$y; $g[0] = 9; print "$x$y @g\n";
