my $c = 0; my $g = sub { $c }; sub bump { $_[0]++ } bump($c) for 1..3; print $g->(), "\n";
