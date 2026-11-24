my $z=0; sub d { my ($a,$b)=@_; return $a/$b } my $r = eval { d(1,$z) }; print defined $r ? "v":"u", "\n";
