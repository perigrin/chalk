our $g = 0; sub bump { $g += 10 } my @l = map { $g = $g + 1; bump(); $g } 1..3; print "@l\n";
