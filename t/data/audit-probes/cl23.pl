my $x = 1; my $g = sub { $x }; sub setx { $_[0] = 12 } setx($x); print $g->(), "\n";
