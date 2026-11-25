our $g=1; sub p { $g } sub t { local $g = 2; return p() . u() } sub u { local $g = $g + 5; p() } print t(), p(), "\n";
