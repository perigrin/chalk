our $g=1; my $c = sub { $g }; my $r=\$g; { local $g=5; print $c->(), $$r } print "\n";
