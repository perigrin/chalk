my $s = "abc"; my @l = (uc($s), $s = "x", uc($s)); print "@l\n";
