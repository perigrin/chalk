our $g=1; sub p { $g } for my $i (1..2) { local $g = $g * 10; print p() } print p(), "\n";
