our $x = 1; { local *x; $x = 5; print $x } print "$x\n";
