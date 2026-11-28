my @a = (1,2,3); sub f { my ($o) = @_; $a[1] = 9; "$o$_[0]" } my @o; for my $x (@a) { push @o, f($x) } print "@o\n";
