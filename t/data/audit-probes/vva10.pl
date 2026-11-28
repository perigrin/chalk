our $x = 1; { local $x = $x + 1; print $x; { local $x = $x + 1; print $x } print $x } print "$x\n";
