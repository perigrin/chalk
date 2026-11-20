my @a = (1, 2, 3); if (@a > 2) { $#a = 0 } print scalar(@a), "\n"; if (@a > 2) { $#a = 5 } print scalar(@a), "\n";
