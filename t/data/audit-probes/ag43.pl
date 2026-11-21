my $h = {a => 3}; sub f { $h->{b} = 9; 0 } print $h->{a}, f(), "\n";
