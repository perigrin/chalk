my $x=1; sub f { $x=7; 0 } my $n = ++$x + f(); print "$n\n";
