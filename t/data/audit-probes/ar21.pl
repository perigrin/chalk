my $x = 1; my $g = sub { $x }; my $set = sub { $_[0] = 5 }; $set->($x); print $g->(), "\n";
