my $x = 1; my $g = sub { $x }; my @l = (7, 8); ($x) = @l; print $g->(), "\n";
