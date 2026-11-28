our $x = 1; { no strict 'refs'; local ${"main::x"} = 2; print $x } print "$x\n";
