my $x=1; sub f { $x=7; 0 } my $n = ($x = 5) + f(); print "$n\n";
