sub f { my ($p) = @_; $p } sub t { tr/a/b/ for $_[0]; 1 } my $s = "a"; my @l = (f($s), t($s), f($s)); print "@l\n";
