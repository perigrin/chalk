our $g = 1; sub f { if ($_[0]) { local $g = 5; return $g } $g } print f(1), f(0), $g, "\n";
