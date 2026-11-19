our $g = 1; sub t { local $g = $g + 1; return $g > 3 ? $g : t() } print t(), $g, "\n";
