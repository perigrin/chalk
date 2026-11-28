our @a = (1,2,3); our $x = 0; { local ($x, @a) = (7, 8, 9); print "$x@a;" } print "$x@a\n";
