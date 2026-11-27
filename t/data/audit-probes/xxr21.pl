my $x = 1; my %o = (r => \$x); sub f { my $o = $_[0]; ${$_[1]{r}} = 5; "$o$_[0]" } print f($x, \%o), "\n";
