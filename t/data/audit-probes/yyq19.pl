our $g=1; sub p { $g } sub t { local $g = 5 if $_[0]; p() } print t(1), t(0), p(), "\n";
