my @a = (1,2,3); my ($x,$y) = (@a[1,2]) = (8); print defined $y ? "d" : "u", "$x@a[0,1]\n";
