sub f { my ($x) = @_; if ($x) { $_[0] = 0 } my ($z) = @_; "$x$z" } my $v = 1; print f($v), $v, "\n";
