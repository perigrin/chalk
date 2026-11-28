my @a = (1,2,3); sub mod { my ($r) = @_; $r->[0] = 9 } mod(\@a); sub cp { my @c = @{$_[0]}; $c[1] = 9 } cp(\@a); print "@a\n";
