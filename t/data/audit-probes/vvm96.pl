our $x = 1; { no strict 'refs'; local ${"x"}; print defined $x ? "d" : "u" } print "$x\n";
