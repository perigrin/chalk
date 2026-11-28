my $x = 1; sub g { $x++; () } my $n = () = g(); my @l = (g(), g()); print "$n ", scalar(@l), " $x\n";
