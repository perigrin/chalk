my $x = 1; my @l; @l = do { ($x, $x++) } for 1; print "@l\n";
