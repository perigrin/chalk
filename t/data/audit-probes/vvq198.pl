my $x = 1; my @l = (do { $x; }, do { $x++ }); print "@l\n";
