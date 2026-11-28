our $depth = 0; sub rec { local $depth = $depth + 1; $_[0] ? rec($_[0] - 1) : $depth } print rec(3), $depth, "\n";
