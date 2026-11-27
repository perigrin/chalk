our $g = 1; sub f { local $g = 2; return sub { $g } } my $c = f(); print $c->(), "\n";
