sub f { my ($x) = @_; for (1..2) { $_[0]++ } my ($z) = @_; "$x$z" } my $v = 1; print f($v), $v, "\n";
