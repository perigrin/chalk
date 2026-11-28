our $x = 1; { no strict 'refs'; local *{"x"}; $x = 5 } print "$x\n";
