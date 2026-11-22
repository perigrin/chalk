my $x=1; my $g=sub{$x}; my $y; ($y,$x)=(5,6); print $g->(), " $y\n";
