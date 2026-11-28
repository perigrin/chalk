sub f { my $n = @_; my $l = $#_; "$n$l$_[-1]" } print f(4, 5, 6), "\n";
