sub f { my ($p,$r) = @_; @$r = (5); "$p" . (defined $_[0] ? "d" : "u") } my @a = (1); print f($a[0], \@a), "\n" if 0; print "ok\n";
