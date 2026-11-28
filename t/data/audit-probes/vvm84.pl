our $x = 1; { no strict 'refs'; local ${"x"} = 2; } print "$x\n";
