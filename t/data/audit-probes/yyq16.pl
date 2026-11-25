our $g=1; sub p { $g } sub t { local $g; $g = 5; p() } print t(), $g, "\n";
