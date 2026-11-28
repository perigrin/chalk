our $x = 1; { local $x = 2; ($x) = (5); print $x } print "$x\n";
