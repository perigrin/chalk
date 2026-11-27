our $g = 1; sub f { $_[0] = 9 } { local $g = 2; f($g); print $g } print $g, "\n";
