my $x = 1; my $g = sub { $x }; { local $_ = 9; $x = $_ } print $g->(), "\n";
