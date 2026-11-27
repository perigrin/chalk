my $x=1; sub f { my @l=@_; $x=9; "@l @_" } print f($x), "\n";
