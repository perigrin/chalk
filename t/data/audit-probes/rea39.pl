our $g=1; my $r = eval { local $g=3; $g*2 }; print "$r $g\n";
