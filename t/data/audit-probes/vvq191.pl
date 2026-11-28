my $x = 1; sub two { my @r = ($x, $x++); @r } my @l = two(); print "@l\n";
