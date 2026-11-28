my $x = 1; sub g { $x++; () } my @l = (5, g(), 6); print "@l\n";
