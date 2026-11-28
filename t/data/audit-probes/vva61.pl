our $x = 1; { local $x = 2 if $x; print $x } print "$x\n";
