our $g = 1; sub f { local $g = $g + 1; $g < 4 ? f() : $g } print f(), $g, "\n";
