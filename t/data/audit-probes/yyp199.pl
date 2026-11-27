my $i=7; my $c = sub { $i }; for $i (1..2) { print $i } print $c->(), "\n";
