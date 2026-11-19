my $x = 1; my $g = sub { $x }; $x++; $x .= "a"; print $g->(), "\n";
