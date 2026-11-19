my @a = (1,2); sub f { $_[0] = 7 } for my $e (@a) { f($e) } print "@a\n";
