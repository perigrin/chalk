our $x = 1; { local $x = 2; { local $x = 3; } print $x } print "$x\n";
