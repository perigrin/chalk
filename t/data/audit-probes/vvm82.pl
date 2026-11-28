our $x = 1; { local $x = 2; ($x, my $t) = (5, 6); print $x } print "$x\n";
