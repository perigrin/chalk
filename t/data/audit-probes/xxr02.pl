sub g { ${$_[0]} = 5 } sub f { my ($p,$r) = @_; g($r); "$p$_[0]" } my $x = 1; print f($x, \$x), "\n";
