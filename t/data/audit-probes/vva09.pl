our ($x,$y) = (1,2); { local ($x,$y); print defined $x ? "d" : "u"; ($x,$y) = (5,6) } print "$x$y\n";
