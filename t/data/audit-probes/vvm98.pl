our $x = 1; { no strict 'refs'; local *{"x"} = \7; print $x } print "$x\n";
