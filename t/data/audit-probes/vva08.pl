our ($x,$y) = (1,2); { local ($x,$y) = (8,9); print "$x$y;" } print "$x$y\n";
