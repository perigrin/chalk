my $x = do { if (0) { "a" } else { "b" } }; my $y = do { 1 if 0 }; print $x, defined $y ? "d[$y]" : "u", "\n";
