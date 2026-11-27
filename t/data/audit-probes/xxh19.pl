sub f { my ($p) = @_; $_[0] = 0; $p } sub ap { &{$_[0]}($_[1]) } my $x = 1; print ap(\&f, $x), $x, "\n";
