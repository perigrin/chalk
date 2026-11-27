sub f { my ($r, $n) = @_; return unless $n; push @$r, $n; f($r, $n - 1) } my @a; f(\@a, 3); print "@a\n";
