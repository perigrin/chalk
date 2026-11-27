my $x = 1; my $r = \$x; sub f { my $o = $_[0]; ${$_[1]} = 5; "$o$_[0]" } print f($x, $r), "\n";
