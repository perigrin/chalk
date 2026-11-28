my $x = 1; my %o = (c => sub { $x = 5 }); sub f { $o{c}->(); $_[0] } print f($x), "\n";
