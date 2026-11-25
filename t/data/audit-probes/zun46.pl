our $g=1; my $r=eval { local $g=2; $g*10 }; print "$r $g\n";
