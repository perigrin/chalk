our $x = 1; { local $x; print defined $x ? "d" : "u"; $x = 4 } print "$x\n";
