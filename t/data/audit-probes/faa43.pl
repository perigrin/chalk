my $x=1; sub g { $x++; 0 } my $v = $x + g() + $x; print "$v\n";
