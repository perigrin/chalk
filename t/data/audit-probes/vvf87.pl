my $x = 1; sub r { return ($x, $x++, $x) } my @l = r(); print "@l\n";
