our ($x,$y) = (1,2); my ($p,$q) = (\$x,\$y); ($$p,$$q) = ($$q,$$p); print "$x$y\n";
