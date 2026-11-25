our $g=1; sub p { $g } sub t { local $g = $g; $g++; p() } print t(), t(), $g, "\n";
