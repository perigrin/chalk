my $x="a"; sub f { $x="z"; "b" } my @l = ($x, f()); print "@l\n";
