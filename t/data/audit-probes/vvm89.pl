our $x = 1; { local ${\ $x} = 2; print $x } print "$x\n";
