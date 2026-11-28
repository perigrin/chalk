my $x = 1; sub f { $x = 5; my %v = @_; $v{k} } print f(k => $x), "\n";
