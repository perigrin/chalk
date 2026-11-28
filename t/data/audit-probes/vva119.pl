our $x = 1; print "$x", do { local $x = 2; $x }, "$x\n";
