sub f { my ($p) = @_; $p } our $g = 1; my $r = \$g; my @l = (f($g), ($$r = 2), f($g)); print "@l\n";
