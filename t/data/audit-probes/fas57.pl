my $x=1; sub n { $x=7; 1 } sub two { my ($a,$b)=@_; "$a$b" } print two($x, n()), "\n";
