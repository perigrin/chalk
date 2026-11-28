use feature 'try'; no warnings; my $x = 1; try { $x = 2; die "z\n" } catch ($e) { $x .= $e } print $x;
