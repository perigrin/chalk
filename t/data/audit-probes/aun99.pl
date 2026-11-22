our $g = 1; sub t { local $g = 5; return $g } my @l = (t(), $g); print "@l\n";
