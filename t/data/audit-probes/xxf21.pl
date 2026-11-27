our $g = 1; for my $v ($g) { local $g = 2; $v = 9; print $g } print $g, "\n";
