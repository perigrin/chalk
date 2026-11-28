my @a = (1,2,3); sub f { \$_[0] } my @o; for my $x (@a) { push @o, f($x) } $$_ *= 2 for @o; print "@a\n";
