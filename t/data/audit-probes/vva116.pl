our $x = 1; { (local $x) = (5, 6); print $x } print "$x\n";
