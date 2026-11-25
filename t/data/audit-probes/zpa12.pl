my $x=1; sub g { $x=9; 1 } my $y = $x + g(); print "$y\n";
