our $x = 1; sub g { $x = 7; () } my @l = (5, g(), 6); print "@l $x\n";
