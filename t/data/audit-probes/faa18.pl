our $x=1; my $r=\$x; { local $x=5; print $$r; } print $$r,"\n";
