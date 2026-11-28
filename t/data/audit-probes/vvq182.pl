our $x = 1; sub c { $x = 5; 0 } my @l = do { ($x, c()) }; print "@l\n";
