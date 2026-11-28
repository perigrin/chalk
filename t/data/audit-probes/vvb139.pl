my @a = (1,2,3); sub f { $_[0] *= 2 } for my $e (@a) { f($e) } print "@a\n";
