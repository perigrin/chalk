our $x = 1; { local $x = 2; for ($x) { $_ = 5 } print $x } print "$x\n";
