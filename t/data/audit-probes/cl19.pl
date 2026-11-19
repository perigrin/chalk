my $x = 1; my $g = sub { $x }; foreach my $v (5) { $x = $v } print $g->(), "\n";
