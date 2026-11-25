my ($x,$y)=(1,2); my $c=sub { $x+$y }; for my $v ($x,$y) { $v*=3; print $c->(), " " } print "\n";
