for my $name (qw(a b)) { no strict 'refs'; *{"get_$name"} = sub { $name } } print get_a(), get_b(), "\n";
