use feature 'try'; no warnings; our $g=1; try { local $g=2; die "x\n" } catch ($e) { print $g, $e }
