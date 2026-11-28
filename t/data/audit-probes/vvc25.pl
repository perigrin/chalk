for my $name (qw(a b)) { no strict 'refs'; *{$name} = sub { uc $name } } print a(), b(), "\n";
