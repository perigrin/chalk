my $x = 1; my @l = do { if (1) { ($x, $x++) } }; print "@l\n";
