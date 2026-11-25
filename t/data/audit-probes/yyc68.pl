my $x=1; sub f { $x=9; 1 } my $n = $x + f(); print "$n\n";
