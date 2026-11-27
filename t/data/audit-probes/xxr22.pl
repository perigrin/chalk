package O; sub new { bless { r => $_[1] }, $_[0] } sub poke { ${$_[0]{r}} = 5 } package main; sub f { my $o = $_[0]; $_[1]->poke; "$o$_[0]" } my $x = 1; print f($x, O->new(\$x)), "\n";
