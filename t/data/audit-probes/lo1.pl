our $g = 1; sub rd { $g } sub t { local $g = 2; my $v = rd(); return $v } print t(), $g, "\n";
