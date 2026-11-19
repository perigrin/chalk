my $x = 1; my $g = sub { $x }; $_ = 3 for $x; print $g->(), "\n";
