our $g = 1; sub t { my $o = $g; inner(); return "$o$g" } sub inner { $g = 2 } print t(), "\n";
