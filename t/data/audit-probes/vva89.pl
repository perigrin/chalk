our $x = 1; our @x = (1,2); { local *x; @x = (9); print scalar(@x) } print "$x@x\n";
