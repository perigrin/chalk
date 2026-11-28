our $g = 1; my @v = eval { local $g = 2; ($g, $g) }; print "@v$g\n";
