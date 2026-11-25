our $g=1; sub p { $g } sub t { $_[0] and local $g = 5; p() } print t(1), t(0), p(), "\n";
