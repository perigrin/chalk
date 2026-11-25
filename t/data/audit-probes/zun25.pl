use feature 'try'; no warnings; our $g=1; sub f { local $g=2; try { die "x\n" } catch ($e) { return $g } } print f(), $g, "\n";
