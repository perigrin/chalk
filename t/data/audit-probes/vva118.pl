our $x = 1; { my $y = local $x = 5; print "$y$x" } print "$x\n";
