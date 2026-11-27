sub f { my $s = 0; $s += $_ for @_; $_[0] = $s } my @a=(1,2,3); f(@a); print "@a\n";
