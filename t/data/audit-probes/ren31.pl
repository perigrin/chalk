my $x=1; my $y=\$x; my $z=$$y; $$y=2; print "$z\n";
