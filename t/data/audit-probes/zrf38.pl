my $x=1; my $r=\$x; undef $r; $x=2; print defined $r ? "d" : "u", "$x\n";
