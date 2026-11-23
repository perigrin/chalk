our $g=1; sub f { local $g=2; 1/$_[0] } for my $z (1,0,1) { eval { f($z) }; print $g }; print "\n";
