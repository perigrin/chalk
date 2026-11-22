my $x = 1; sub f { $x = 2 } my $y = $x; f(); print "$y $x\n";
